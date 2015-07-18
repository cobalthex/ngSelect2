'use strict'

# generalized select2 for select elements with pagination, used for selecting from a list of objects (passed through html or as a function)
# requires a function returning javascript objects or a collection of objects with
#    1) an id field (if not 'id', specify id-field="'whatever'")
#    2) an text field for search and display (if not 'text', specify text-field="'whatever'")
#  or an object where all keys will convert to ids and all values will convert to texts
#  If only passing in values, both id and text will be set to value
# Note: any classes applied to the select will be removed and applied to the visible element

### Attributes: (All optional)
multiple       : Specify whether or not this select field supports multiple options
disabled       : Specify whether or not the dropdown is disabled (ng-disabled works)
placeholder    : Specify a placeholder for the dropdown
page-size      : Specify the number of items that are loaded during pagination (Defaults to 20)
allow-clear    : Allow there to be a clear button that allows for an empty value (Defaults to false)
close-on-select: Enable or disable closing when an item is selected (Defaults to true)

id-field       : A custom field name to specify an item's ID
text-field     : A custom field name to specify an item' text
disabled-field : A custom field name to specify if an item is disabled

prepend-options: Prepend scope.options before any HTML options (defaults to false)
###

angular.module('bwCommon').directive 'select2', ($timeout) ->
  restrict  : 'A'
  require   : ['select', 'ngModel']
  priority  : 101

  scope:
    options: '=' # a function that returns a list of available options
    exclude: '=' # exclude items from the options (Must match those coming in as options)

  link: (scope, element, attrs, ctrl) ->
    selectCtrl = ctrl[0]
    ngModelCtrl = ctrl[1]
    multiple = attrs.multiple isnt undefined or false

    ### setup ###

    # remove included classes from the element, these will be added to the select2 container (see below)
    element.attr 'class', ''

    # add in-html options (to the front)
    htmlOptions = jQuery.map element.find('option'), (val, i) ->
      return _.object [[ attrs.idField or 'id', val.value or val.textContent or i ], [ attrs.textField or 'text', val.textContent or '' ]]

    ### functions ###

    # Set a visible value for the select box without actually selecting anything
    scope.setVisibleValue = (visVal) ->
      if not visVal
        return

      if not angular.isArray visVal
        visVal = [visVal]

      visVal = _.map visVal, (val) ->
        id: val.id or val
        text: val.text or val

      element.data('select2').selection.update visVal
      return

    # return a normalized version of an option's id/text/disabled
    normalizeOption = (option) ->
      id      : option[attrs.idField or 'id'] or option or ''
      text    : option[attrs.textField or 'text'] or option or ''
      disabled: option[attrs.disabledField or 'disabled'] or false

    # fetch a page of results from the 'options'
    query = (params, callback) ->
      options = if angular.isFunction scope.options then scope.options() else scope.options
      if not options
        options = []

      # allow objects to be used via their key: value
      if (not angular.isArray options) and angular.isObject options
        options = _.map options, (val, key) ->
          id: key
          text: val

      if attrs.prependOptions
        options.push htmlOptions...
      else
        options.unshift htmlOptions...

      # standard paging size
      pageSize = scope.pageSize or 20

      # optional search
      if params.term
        options = _.filter options, (o) =>
          return not o.disabled and this.matches params, o

      # optional exclusions
      if scope.exclude
        exclude = if angular.isArray scope.exclude then scope.exclude else [scope.exclude]

        idf = attrs.idField or 'id'
        txf = attrs.textField or 'text'
        options = _.filter options, (o) ->
          return not (_.filter exclude, (val) ->
            if angular.isObject val
              return (val[idf] == o[idf] and val[txf] == o[txf]) # compare only id and text as other fields may have been added that are not relevant
            else
              return val == o[idf] # simple value comparison
          .length)

      if not params.page
        params.page = 1

      indexStart = (params.page - 1) * pageSize
      indexEnd   = params.page * pageSize
      slicedOptions = options.slice indexStart, indexEnd

      paginatedOptions = (normalizeOption o for o in slicedOptions)

      hasMore = indexEnd < options.length
      callback
        results: paginatedOptions
        more   : hasMore
      return

    # select2 recommends (requires) loading through AMD
    jQuery.fn.select2.amd.require ['select2/data/array', 'select2/utils'], (ArrayData, Utils) ->
      CustomData = ($element, options) ->
        CustomData.__super__.constructor.call this, $element, options
        return
      Utils.Extend CustomData, ArrayData

      CustomData.prototype.query = query

      # initialize select2
      element.select2
        dataAdapter  : CustomData
        placeholder  : attrs.placeholder or ''
        allowClear   : attrs.allowClear isnt undefined and attrs.allowClear isnt false
        closeOnSelect: (attrs.closeOnSelect isnt undefined and attrs.closeOnSelect isnt false) or true
        multiple     : multiple
        width        : '100%'

      # move classes from the select to the visible select2 element
      element.data('select2').$container.addClass attrs.class

      return
    , "ngSelect2", true # force this require to run synchronously

    # events
    element.on '$destroy', ->
      element.select2 'destroy'
      return

    return
