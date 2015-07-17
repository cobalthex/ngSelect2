'use strict'

# generalized select2 with pagination, used for selecting from a list of objects (passed through html or as a function)
# requires a function returning javascript objects with
#    1) an id field (if not 'id', specify id-name="'whatever'")
#    2) an text field for search and display (if not 'text', specify text-name="'whatever'")

### Attributes: (All optional)
multiple     : Specify whether or not this select field supports multiple options
disabled     : Specify whether or not the dropdown is disabled (ng-disabled works)
placeholder  : Specify a placeholder for the dropdown
pageSize     : Specify the number of items that are loaded during pagination (Defaults to 20)

idField      : A custom field name to specify an item's ID
textField    : A custom field name to specify an item' text
disabledField: A custom field name to specify if an item is disabled
###

angular.module('bwCommon').directive 'select2', ($timeout) ->
  template  : '<select class="select2-wrapper"></select>'
  restrict  : 'E'
  transclude: true

  scope:
    choice      : '=ngModel'
    options     : '&'
    visibleValue: '@'

  link: (scope, element, attrs, ctrl, transcludeFn) ->
    elem = element.find '.select2-wrapper'

    multiple = attrs.multiple isnt undefined or false

    # Set a visible value for the select box without actually selecting anything
    scope.setVisibleValue = (visVal) ->
      if not visVal
        return

      if not angular.isArray visVal
        visVal = [visVal]

      visVal = _.map visVal, (val, i) ->
        id: val.id or val
        text: val.text or val

      elem.data('select2').selection.update visVal
      return

    # return a normalized version of an option's id/text/disabled
    normalizeOption = (option) ->
      id      : option[scope.idField or 'id'] or ''
      text    : option[scope.textField or 'text'] or ''
      disabled: option[scope.disabledField or 'disabled'] or false

    # in-html options
    opts = jQuery.map transcludeFn().filter('option'), (val, i) ->
      id: val.value or i
      text: val.textContent or ''
      selected: val.selected or false

    # fetch a page of results from the 'options'
    query = (params, callback) ->
      options = scope.options() or opts

      # standard paging size
      pageSize = scope.pageSize or 20

      if params.term
        options = _.filter options, (o) =>
          return not o.disabled and this.matches params, o

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
      elem.select2
        dataAdapter      : CustomData
        placeholder      : attrs.placeholder
        multiple         : multiple
        width            : '100%'
        debug            : true

      # set default value
      def = _.filter scope.options() or opts, (val, i) ->
        return val.selected == true
      $timeout () ->
        elem.data('select2').dataAdapter.select d for d in def
        return

      return
    , "PaginatedDropdown", true # force this require to run synchronously

    flag = false # flag to prevent infinite loop between scope and dom events (mutual recursion)

    # events
    elem
    .on '$destroy', ->
      elem.select2 'destroy'
      return
    .on 'change', (ev) ->
      if not flag
        flag = true
        scope.choice = elem.val()
        scope.$apply()
      else
        flag = false
      return

    watchFn = if multiple then '$watchCollection' else '$watch'
    scope[watchFn] 'choice', (choice) ->
      if not flag
        flag = true
        elem.val(choice).trigger('change')
      else
        flag = false
      return

    attrs.$observe 'disabled', (disabled) ->
      elem.prop 'disabled', disabled
      return

    return
