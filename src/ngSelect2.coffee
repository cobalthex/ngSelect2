'use strict'

# generalized select2 for select elements with pagination, used for selecting from a list of objects (passed through html or as a function)
# requires a function returning javascript objects or a collection of objects with
#    1) an id field (if not 'id', specify id-field="'whatever'")
#    2) an text field for search and display (if not 'text', specify text-field="'whatever'")
#  or an object where all keys will convert to ids and all values will convert to texts
#  If only passing in values, both id and text will be set to value
# Note: any classes applied to the select will be removed and applied to the visible element

# (Select2Template is defined below)

### Attributes: (All optional)
multiple            : Specify whether or not this select field supports multiple options
disabled            : Is the select2 disabled?
page-size           : Specify the number of items that are loaded during pagination (Defaults to 20)
allow-clear         : Allow there to be a clear button that allows for an empty value (Defaults to false)
close-on-select     : Enable or disable closing when an item is selected (Defaults to true)

id-field            : A custom field name to specify an item's ID
text-field          : A custom field name to specify an item' text
disabled-field      : A custom field name to specify if an item is disabled

prepend-options-list: Prepend scope.options before any HTML options (defaults to false)
###

angular.module('bwCommon').directive 'select2', ($timeout, $compile, $q) ->
  restrict  : 'E'
  require   : ['?ngModel']
  priority  : 101
  template  : '<select></select>'
  transclude: true

  scope:
    options    : '=' # a function that returns a list of available options
    exclude    : '=' # exclude items from the options (Must match those coming in as options). All values are converted to strings when testing
    placeholder: '@' # supports objects (in the same format as those in options) or text
    params     : '=?' # pass in a set of parameters instead of specifying attributes (useful for templating) - overrides all other parameters set

  link: (scope, element, attrs, ctrl, transcludeFn) ->
    select = element.find 'select' # the select element that select2 uses

    if not scope.params
      scope.params = {}

    # use scope params - scope variables are used in place
    scope.params.multiple = attrs.multiple ? scope.params.multiple
    scope.params.disabled = attrs.disabled ? scope.params.disabled
    scope.params.pageSize = attrs.pageSize ? scope.params.pageSize
    scope.params.allowClear = attrs.allowClear ? scope.params.allowClear
    scope.params.idField = attrs.idField ? scope.params.idField
    scope.params.textField = attrs.textField ? scope.params.textField
    scope.params.disabledField = attrs.disabledField ? scope.params.disabledField
    scope.params.prependOptionsList = attrs.prependOptionsList ? scope.params.prependOptionsList

    ngModelCtrl = ctrl[0]

    ### functions ###

    extendObj = _.partialRight _.assign, (value, other) ->
      return (if _.isUndefined value then other else value)

    isParamEnabled = (paramName) -> # check if an attribute is enabled, supports non-valued attributes
      return scope.params[paramName] isnt undefined and paramName.toLowerCase() isnt 'false'
    moveAttr = (attrName) -> # move an attribute to the select element if it exists on the original
      if attrs[attrName]?
        select.attr attrName, attrs[attrName]
        element.removeAttr attrName
      return
    moveAttrs = () -> # move a list of attributes, passed as arguments
      moveAttr attrName for attrName in arguments

    # Set a visible value for the select box without actually selecting anything
    scope.setVisibleValue = (visVal) ->
      if not visVal
        return

      if not angular.isArray visVal
        visVal = [visVal]

      visVal = _.map visVal, (val) ->
        id: val.id or val
        text: val.text or val

      select.data('select2').selection.update visVal
      return

    # return a normalized version of an option's id/text/disabled
    normalizeOption = (option) ->
      id      : option[scope.params.idField or 'id'] or option or ''
      text    : option[scope.params.textField or 'text'] or option or ''
      disabled: option[scope.params.disabledField or 'disabled'] or false
      item    : option

    # Exclude options (via object-id/text or value-id compare)
    excludeOptions = (options, exclusions) ->
      exclude = if angular.isArray exclusions then exclusions else [exclusions]
      idf = scope.params.idField or 'id'
      txf = scope.params.textField or 'text'
      return _.filter options, (o) ->
        return not (_.filter exclude, (val) ->
          if angular.isObject val
            # compare only id and text as other fields may have been added that are not relevant
            return (val[idf] == o[idf] and val[txf] == o[txf])
          else
            return val.toString() == o[idf].toString() # simple (string) value comparison
        .length)

    # fetch a page of results from the 'options'
    query = (qparams, callback) ->
      params =
        term: qparams.term or ''
        page: qparams.page or 1

      options = scope.options or []
      if angular.isFunction options
        options = options(params)
      else if angular.isArray options
        options = _.clone(options, true)

      defer = $q.when options
      defer.then (data) ->
        results = data.results or data

        # allow objects to be used via their key: value
        if (not angular.isArray results) and angular.isObject results
          results = _.map results, (val, key) ->
            id  : key
            text: val
            item: _.object([[key, val]])

        #prepend or append the options array (from options="...")
        if isParamEnabled 'prependOptionsList'
          results.push htmlOptions...
        else
          results.unshift htmlOptions...

        if data.results? # was originally deferred, do not paginate (is done already)
          # optionally exclude options
          if scope.params?.exclude or scope.exclude
            results = excludeOptions results, scope.params?.exclude or scope.exclude

          callback
            results: (normalizeOption o for o in results)
            pagination:
              more: data.more
        else
          # optional search
          if qparams.term
            results = _.filter results, (o) =>
              return not o.disabled and this.matches params, o

          # exclude options (run after filtering by search to limit processing)
          if scope.params?.exclude or scope.exclude
            results = excludeOptions results, scope.params?.exclude or scope.exclude

          pageSize = scope.params.pageSize or 20
          indexStart = (qparams.page - 1) * pageSize
          indexEnd   = params.page * pageSize
          slicedOptions = results.slice indexStart, indexEnd

          hasMore = indexEnd < options.length
          callback
            results: (normalizeOption o for o in slicedOptions)
            pagination:
              more: hasMore
        return

    resultsTemplateFn = (item) ->
      cs = scope.$new(true) # create a child isolated scope
      cs = extendObj cs, item
      tpl = angular.element '<span>'
      $timeout ->
        tpl.html (angular.element resTemplate or template).html()
        $compile(tpl)(cs)
      return tpl

    selectionTemplateFn = (item) ->
      cs = scope.$new(true) # create a child isolated scope
      cs = extendObj cs, item
      tpl = angular.element '<span>'
      $timeout ->
        tpl.html (angular.element selTemplate or template).html()
        $compile(tpl)(cs)
      return tpl

    ### setup ###

    multiple = isParamEnabled 'multiple'

    # remove included classes from the element, these will be added to the select2 container (see below)
    select.attr 'class', ''

    txcl = transcludeFn()

    _htmlOptions = txcl.filter('option')
    # add in-html options
    htmlOptions = jQuery.map _htmlOptions, (val, i) ->
      return _.object [[ scope.params.idField or 'id', val.value or val.textContent or i ], [ scope.params.textField or 'text', val.textContent or '' ]]

    selTemplate = txcl.filter('select2-template[selection]')[0] or undefined # an explicit template for selected results (includes placeholders)
    resTemplate = txcl.filter('select2-template[results]')[0] or undefined # an explicit template for all options (includes text like 'loading...')
    template = txcl.filter('select2-template').not(selTemplate).not(resTemplate)[0] or undefined # a default/fallback template if one or both of the above are not specified

    # Load in all dependencies via amd -
    jQuery.fn.select2.amd.require ['select2/utils', 'select2/data/array', 'select2/results', 'select2/dropdown/infiniteScroll'],
    (Utils, ArrayData, ResultsData, InfiniteScroll) ->
      CustomData = ($element, options) ->
        CustomData.__super__.constructor.call this, $element, options
        return
      Utils.Extend CustomData, ArrayData

      CustomData.prototype.query = query
      resultsAdapter = Utils.Decorate ResultsData, InfiniteScroll # support infinite scrolling (pagination)

      # initialize select2 - All data processing can be done through ajax (as opposed to a custom DataAdapter)
      s2o =
        dataAdapter   : CustomData
        resultsAdapter: resultsAdapter
        placeholder   : normalizeOption(scope.placeholder or scope.params.placeholder or '')
        allowClear    : isParamEnabled 'allowClear'
        closeOnSelect : scope.params.closeOnSelect?.toLowerCase() isnt 'false'
        multiple      : multiple
        width         : '100%'

      if resTemplate or template
        s2o.templateResult    = resultsTemplateFn
      if selTemplate or template
        s2o.templateSelection = selectionTemplateFn

      select.select2 s2o

      # set default value
      $timeout ->
        sel = jQuery.map _htmlOptions.filter('[selected]'), (val) ->
          id: val.value or val.textContent or ''
          text: val.textContent or ''
        select.data('select2').dataAdapter.select s for s in sel

      # move classes from the select to the visible select2 element
      select.data('select2').$container.addClass attrs.class
      # copy HTML form attributes over

      moveAttrs 'autofocus', 'form', 'name' #, 'required'

      ### events / observers ###

      select.on '$destroy', ->
        select.select2 'destroy'
        return

      select.on 'change.select2', ->
        if ngModelCtrl?
          ngModelCtrl.$setViewValue select.val()
        return

      attrs.$observe 'disabled', (disabled) ->
        select.prop 'disabled', disabled isnt undefined and disabled.toString().toLowerCase() isnt 'false'
        return

      return
    return

# An optional template directive for select2 elements. Must be inside the original select2 select element
# Any HTML inside of this element is run through $compile with an isolated child-scope and used as the template for the parent select2 element
angular.module('bwCommon').directive 'select2Template', ($timeout) ->
  restrict  : 'E'
  terminal  : true
  priority  : 1000
