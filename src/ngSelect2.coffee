'use strict'

#ngSelect2

# ngSelect2 is an Angular JS wrapper for the select2 4.0+ library.
# This library supports many of the features of the selectt2 library and adds features like
#   angular based templating and pagination
# It also supports options provided through HTML, arrays, objects, functions, and promises

# (Select2Template is defined below)

### Attributes: (All optional)
tags                : Allow for custom (typed) results
multiple            : Specify whether or not this select field supports multiple options
disabled            : Is the select2 disabled?
page-size           : Specify the number of items that are loaded during pagination (Defaults to 20)
allow-clear         : Display a button to clear the selected value (Defaults to false)
close-on-select     : Enable or disable closing when an item is selected (Defaults to true)
max-selection-length: When multiple is specified, this will limit the number of results
dir                 : Direction of text (LTR (default) or RTL)

id-field            : A custom field name to specify an item's ID
text-field          : A custom field name to specify an item' text
disabled-field      : A custom field name to specify if an item is disabled

prepend-options-list: Prepend scope.options before any HTML options (defaults to false)
###

### Scope expressions:
selection  : An alias of ngModel
options    : A function that returns a list of available options
exclude    : Exclude items from the options (Must match those coming in as options).
             All values are converted to strings when testing
placeholder: Supports objects (in the same format as those in options) or text
params     : Pass in a set of parameters instead of specifying attributes (useful for templating)
             overrides all other parameters set
open       : When this is true, the select2 dropdown will open
close      : When this is true, the select2 dropdown will close

onOpen     : An event callback that is called when the select2 dropdown is opened
onClose    : An event callback that is called when the select2 dropdown is opened
onFocus    : An event callback that is called when the select2 element gains focus
onBlur     : An event callback that is called when the select2 element loses focus
onChange   : An event callback that is called when the select2 value changes (ng-change also works)
onDisabled : An event callback that is called when the select2 element is disabled
onEnabled  : An event callback that is called when the select2 element is enabled
###

### TODO

Dynamic placeholders
Open on focus

###

angular.module('bwCommon').directive 'select2', ($timeout, $compile, $q) ->
  restrict  : 'EA'
  require   : ['?ngModel']
  priority  : 101
  template  : '<select></select>'
  transclude: true

  scope:
    # Explanations above
    selection  : '=ngModel'
    options    : '='
    exclude    : '='
    placeholder: '@'
    params     : '=?'
    open       : '=?'
    close      : '=?'

    onOpen     : '&'
    onClose    : '&'
    onFocus    : '&'
    onBlur     : '&'
    onChange   : '&'
    onDisabled : '&'
    onEnabled  : '&'

  link: (scope, element, attrs, ctrl, transcludeFn) ->
    select = element.find 'select' # the select element that select2 uses

    ### Functions ###

    # Check if an attribute is enabled, supports non-valued attributes
    isParamEnabled = (paramName) ->
      return scope.params[paramName] isnt undefined and paramName.toLowerCase() isnt 'false'

    # Extend an object with preferences towards the original
    extendObj = _.partialRight _.assign, (value, other) ->
      return (if _.isUndefined value then other else value)

    moveAttr = (attrName) -> # move an attribute to the select element if it exists on the original
      if attrs[attrName]?
        select.attr attrName, attrs[attrName]
        element.removeAttr attrName
      return
    moveAttrs = -> # move a list of attributes, passed as arguments
      moveAttr attrName for attrName in arguments

    # Set a visible value for the select box without actually selecting anything
    scope.setVisibleValue = (visVal) ->
      if not visVal
        return

      if not angular.isArray visVal
        visVal = [visVal]

      visVal = _.map visVal, (val) ->
        id: val.id ? val
        text: val.text ? val

      select.data('select2').selection.update visVal
      return

    # return a normalized version of an option's id/text/disabled
    normalizeOption = (option) ->
      id      : option[scope.params.idField ? 'id'] ? option or ''
      text    : (option[scope.params.textField ? 'text'] ? option or '').toString()
      disabled: option[scope.params.disabledField ? 'disabled'] ? false
      item    : option

    # Exclude options (via function(options), object-id/text, or value-id compare)
    # returns all of the options not excluded
    excludeOptions = (options, exclusions) ->
      if angular.isFunction exclusions
        return exclusions options
      else
        exclude = if angular.isArray exclusions then exclusions else [exclusions]
        idf = scope.params.idField ? 'id'
        txf = scope.params.textField ? 'text'
        return _.filter options, (obj) ->
          return not (_.filter exclude, (val) ->
            if angular.isObject val
              # compare only id and text as other fields may have been added that are not relevant
              return (val[idf] == obj[idf] and val[txf] == obj[txf])
            else
              return val.toString() == obj[idf].toString() # simple (string) value comparison
          .length)

    # fetch a page of results from the 'options'
    query = (qparams, callback) ->
      params =
        term: qparams.term or ''
        page: qparams.page or 1

      options = scope.options or []
      if angular.isFunction options
        options = options params
      else if angular.isArray options
        # if not cloned, any results added temporarily will not be temporary
        options = _.clone options, true

      defer = $q.when options
      defer.then (data) =>
        results = data.results ? data

        # allow objects to be used via their key: value
        if (not angular.isArray results) and angular.isObject results
          results = _.map results, (val, key) ->
            id  : key
            text: val
            item: _.object([[key, val]])

        #prepend or append the options array (from options="...")
        if isParamEnabled 'prependOptionsList'
          results = results.concat htmlOptions
        else
          results = htmlOptions.concat results

        # tagging
        tag = jQuery.trim params.term
        if isParamEnabled('tags') and tag.length
          results.unshift tag

        results = (normalizeOption o for o in results)

        if data.results? # was originally deferred, do not paginate (is done already)
          # optionally exclude options
          if scope.params?.exclude ? scope.exclude
            results = excludeOptions results, scope.params?.exclude ? scope.exclude
          callback
            results: results
            pagination:
              more: data.more
        else
          # optional search
          if params.term.length
            results = _.filter results, (o) =>
              return not o?.disabled and this.matches params, o

          # exclude options (run after filtering by search to limit processing)
          if scope.params?.exclude ? scope.exclude
            results = excludeOptions results, scope.params?.exclude ? scope.exclude

          pageSize = scope.params.pageSize or 20
          indexStart = (qparams.page - 1) * pageSize
          indexEnd   = params.page * pageSize
          slicedOptions = results.slice indexStart, indexEnd

          hasMore = indexEnd < options.length
          callback
            results: slicedOptions
            pagination:
              more: hasMore
        return

    templateFn = (template, item) ->
      if not item.item? # not item, just return text (placeholders, loading text, etc)
        return item.text

      cs = scope.$new(true) # create an isolated child scope
      cs = extendObj cs, item
      tpl = angular.element '<span>'
      $timeout ->
        tpl.html angular.element(template).html()
        $compile(tpl)(cs)
      return tpl

    ### Setup ###

    if not scope.params
      scope.params = {}

    # use scope params - scope variables are used in place
    scope.params.tags               = attrs.tags               ? scope.params.tags
    scope.params.multiple           = attrs.multiple           ? scope.params.multiple
    scope.params.disabled           = attrs.disabled           ? scope.params.disabled
    scope.params.prependOptionsList = attrs.prependOptionsList ? scope.params.prependOptionsList
    scope.params.maxSelectionLength = attrs.maxSelectionLength ? scope.params.maxSelectionLength
    scope.params.allowClear         = attrs.allowClear         ? scope.params.allowClear
    scope.params.pageSize           = attrs.pageSize           ? scope.params.pageSize
    scope.params.dir                = attrs.dir                ? scope.params.dir
    scope.params.idField            = attrs.idField            ? scope.params.idField
    scope.params.textField          = attrs.textField          ? scope.params.textField
    scope.params.disabledField      = attrs.disabledField      ? scope.params.disabledField

    ngModelCtrl = ctrl[0]

    multiple = isParamEnabled 'multiple'

    # remove included classes from the element
    # these will be added to the select2 container (see below)
    select.attr 'class', ''

    txcl = transcludeFn()

    _htmlOptions = txcl.filter('option')
    # add in-html options
    htmlOptions = jQuery.map _htmlOptions, (val, i) ->
      _id = [ scope.params.idField ? 'id', val.value ? val.textContent or '' ]
      _text = [ scope.params.textField ? 'text', val.textContent or '' ]
      return _.object [ _id, _text ]

    # an explicit template for selected results (includes placeholders)
    selTemplate = txcl.filter('select2-template[selection]')[0] or undefined
    # an explicit template for all options (includes text like 'loading...')
    resTemplate = txcl.filter('select2-template[results]')[0] or undefined
    # a default/fallback template if one or both of the above are not specified
    template = txcl.filter('select2-template').not(selTemplate).not(resTemplate)[0] or undefined

    # load in all dependencies via amd -
    jQuery.fn.select2.amd.require [
      'select2/utils'
      'select2/data/array'
      'select2/results'
      'select2/dropdown/infiniteScroll'
    ],
    (Utils, ArrayData, ResultsData, InfiniteScroll) ->
      CustomData = ($element, options) ->
        CustomData.__super__.constructor.call this, $element, options
        return
      Utils.Extend CustomData, ArrayData

      CustomData.prototype.query = query
      # support infinite scrolling (pagination)
      resultsAdapter = Utils.Decorate ResultsData, InfiniteScroll

      # initialize select2
      s2o =
        dataAdapter       : CustomData
        resultsAdapter    : resultsAdapter
        placeholder       : (scope.placeholder or scope.params.placeholder or '')
        allowClear        : isParamEnabled 'allowClear'
        closeOnSelect     : scope.params.closeOnSelect?.toLowerCase() isnt 'false'
        multiple          : multiple
        width             : '100%'
        maxSelectionLength: scope.params.maxSelectionLength or Infinity
        dir               : scope.params.dir or 'ltr'

      if resTemplate or template
        s2o.templateResult    = (item) -> templateFn (resTemplate or template), item
      if selTemplate or template
        s2o.templateSelection = (item) -> templateFn (selTemplate or template), item

      select.select2 s2o

      s2 = select.data('select2') # select2 internals

      # set default value
      $timeout ->
        jQuery.each _htmlOptions.filter('[selected]'), ->
          item =
            id: this.value or this.textContent or ''
            text: this.textContent or ''
          s2.dataAdapter.select
            id: item.id
            text: item.text
            item: item
        return

      # move classes from the select to the visible select2 element
      s2.$selection.addClass attrs.class
      # copy HTML form attributes over

      moveAttrs 'autofocus', 'form', 'name', 'required'

      ### Events / Observers ###
      attrs.$observe 'disabled', (disabled) ->
        disabled = disabled isnt undefined and disabled.toString().toLowerCase() isnt 'false'
        select.prop 'disabled', disabled
        if disabled
          scope.onDisabled()
        else
          scope.onEnabled()
        return

      select.on '$destroy', ->
        select.select2 'destroy'
        return

      select.on 'select2:open', ->
        # this will fire twice - https://github.com/select2/select2/issues/3503
        scope.onOpen()
        return
      select.on 'select2:close', ->
        scope.onClose()
        return

      flag = 0
      select.on 'change.select2', ->
        if flag == 1
          flag = 0
          return
        if flag == 2
          return

        flag = 1
        sv = (s.item for s in select.select2('data'))
        if not multiple
          sv = sv[0]
        $timeout ->
          scope.selection = sv
          scope.onChange sv
          return
        return

      # set selected value programatically
      scope.$watch 'selection', (selection) ->
        if not selection?
          return

        if flag == 1
          flag = 0
          return

        flag = 2
        if angular.isArray selection
          for s in selection when s?
            s2.dataAdapter.select
              id: s.id ? s
              text: s.text ? s
              item: s
        else
          s2.dataAdapter.select
            id: selection.id ? selection
            text: selection.text ? selection
            item: selection
        flag = 1
        return

      s2.$selection.on 'focusin', ->
        scope.onFocus()
        return
      s2.$selection.on 'focusout', ->
        scope.onBlur()
        return

      scope.$watch 'open', (open) ->
        if open then select.select2 'open'
        return
      scope.$watch 'close', (close) ->
        if close then select.select2 'close'
        return

      return
    return

# An optional template directive for select2 elements
# Must be inside the original select2 select element
# Scope variables are in the format of:
# id
# text
# item (original value)
angular.module('bwCommon').directive 'select2Template', ($timeout) ->
  restrict  : 'EA'
  terminal  : true
  priority  : 1001
