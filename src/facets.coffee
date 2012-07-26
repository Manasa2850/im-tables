scope 'intermine.snippets.facets', {
    OnlyOne: _.template """
            <div class="alert alert-info im-all-same">
                All <%= count %> values are the same: <strong><%= item %></strong>
            </div>
        """
}
scope "intermine.results", (exporting) ->

    ##----------------
    ## Returns a fn to calculate a point Z(x), 
    ## the Probability Density Function, on any normal curve. 
    ## This is the height of the point ON the normal curve.
    ## For values on the Standard Normal Curve, call with Mean = 0, StdDev = 1.
    NormalCurve = (mean, stdev) ->
        (x) ->
            a = x - mean
            Math.exp(-(a * a) / (2 * stdev * stdev)) / (Math.sqrt(2 * Math.PI) * stdev)

    MORE_FACETS_HTML = """
        <i class="icon-plus-sign pull-right" title="Showing top ten. Click to see all values"></i>
    """
    FACET_TITLE = _.template """
        <dt><i class="icon-chevron-right"></i><%= title %></dt>
    """
    FACET_TEMPLATE = _.template """
        <dd>
            <a href=#>
                <b class="im-facet-count pull-right">
                    (<%= count %>)
                </b>
                <%= item %>
            </a>
        </dd>
    """

    exporting class ColumnSummary extends Backbone.View
        tagName: 'div'
        className: "im-column-summary"
        initialize: (facet, @query) ->
            if _(facet).isString()
                @facet =
                    path: facet
                    title: facet.replace(/^[^\.]+\./, "").replace(/\./g, " > ")
                    ignoreTitle: true
            else
                @facet = facet


        render: =>
            attrType = @query.getPathInfo(@facet.path).getType()
            if attrType in intermine.Model.NUMERIC_TYPES
                clazz = NumericFacet
                #else if attrType in intermine.Model.BOOLEAN_TYPES
                #clazz = BooleanFacet
            else
                clazz = FrequencyFacet
            initialLimit = 400 # items
            fac = new clazz(@query, @facet, initialLimit, @noTitle)
            @$el.append fac.el
            fac.render()
            this

    exporting class FacetView extends Backbone.View
        tagName: "dl"
        initialize: (@query, @facet, @limit, @noTitle) ->
            @query.on "change:constraints", @render
            @query.on "filter:summary", @render

        render: =>
            unless @noTitle
                @$dt = $(FACET_TITLE @facet).appendTo @el
                @$dt.click =>
                    @$dt.siblings().slideToggle()
                    @$dt.find('i').first().toggleClass 'icon-chevron-right icon-chevron-down'
            this

    exporting class FrequencyFacet extends FacetView
        render: (filterTerm = "") ->
            return if @rendering
            @rendering = true
            @$el.empty()
            super()
            $progress = $ """
                <div class="progress progress-info progress-striped active">
                    <div class="bar" style="width:100%"></div>
                </div>
            """
            $progress.appendTo @el
            promise = @query.filterSummary @facet.path, filterTerm, @limit, (items, total, filteredTotal) =>
                @query.trigger "got:summary:total", @facet.path, total, items.length, filteredTotal
                $progress.remove()
                @$dt?.append " (#{total})"
                hasMore = if items.length < @limit then false else (total > @limit)
                if hasMore
                    more = $(MORE_FACETS_HTML).appendTo(@$dt)
                                        .tooltip( {placement: "left"} )
                                        .click (e) =>
                        e.stopPropagation()
                        got = @$('dd').length
                        show = @$('dd').first().is ':visible'
                        @query.summarise @facet.path, (items) =>
                            (@addItem item).toggle(show) for item in items[got..]
                        more.tooltip('hide').remove()

                if total <= 12 and not @query.canHaveMultipleValues @facet.path
                    pf = new PieFacet(@query, @facet, items, hasMore, filterTerm)
                    @$el.append pf.el
                    pf.render()
                else
                    hf = new HistoFacet(@query, @facet, items, hasMore, filterTerm)
                    @$el.append hf.el
                    hf.render()

                if total <= 1
                    @$el.empty()
                    if total is 1
                        @$el.append intermine.snippets.facets.OnlyOne items[0]
                    else
                        @$el.append("No results")

                @rendering = false
            promise.fail @remove
            this

        addItem: (item) =>
            $dd = $(FACET_TEMPLATE(item)).appendTo @el
            $dd.click =>
                @query.addConstraint
                    title: @facet.title
                    path: @facet.path
                    op: "="
                    value: item.item
            $dd


    exporting class NumericFacet extends FacetView

        events:
            'click': (e) -> e.stopPropagation()

        className: "im-numeric-facet"

        chartHeight: 50

        render: ->
            super()
            @range = new Backbone.Model()
            @container = @make "div"
                class: "facet-content im-facet"
            @$el.append(@container)
            canvas = @make "div"
            @canvas = $(canvas).mouseout () => @_selecting_paths_ = false
            $(@container).append canvas
            @paper = Raphael(canvas, @$el.width(), @chartHeight)
            @throbber = $ """
                <div class="progress progress-info progress-striped active">
                    <div class="bar" style="width:100%"></div>
                </div>
            """
            @throbber.appendTo @el
            promise = @query.summarise @facet.path, @handleSummary
            promise.fail @remove
            this

        handleSummary: (items, total) =>
            @throbber.remove()
            summary = items[0]
            if summary.item?
                if items.length > 1
                    # A numerical column configured to present as a string column.
                    hasMore = if items.length < @limit then false else (total > @limit)
                    @paper.remove()
                    hf = new HistoFacet @query, @facet, items, hasMore, ""
                    @$el.append hf.el
                    return hf.render()
                else
                    # Dealing with the single value edge case here...
                    return @$el.empty().append intermine.snippets.facets.OnlyOne(summary)
            @mean = parseFloat(summary.average)
            @dev = parseFloat(summary.stdev)
            @max = summary.max
            @min = summary.min
            if summary.count?
                @drawChart(items)
            else
                @drawCurve()
            @drawStats()
            @drawSlider()

        drawStats: () =>
            $(@container).append """
                <table class="table table-bordered table-condensed">
                    <thead>
                        <tr>
                            <th>Min</th>
                            <th>Max</th>
                            <th>Mean</th>
                            <th>Standard Deviation</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>#{ @min }</td>
                            <td>#{ @max }</td>
                            <td>#{ @mean.toFixed(5) }</td>
                            <td>#{ @dev.toFixed(5) }</td>
                        </tr>
                    </tbody>
                </table>
            """

        drawSlider: =>
            $(@container).append """
                <label>Range:</label>
                <input type="text" class="im-range-min input" value="#{@min}">
                <span>...</span>
                <input type="text" class="im-range-max input" value="#{@max}">
                <button class="btn btn-primary disabled">Apply</button>
                <button class="btn btn-cancel disabled">Reset</button>
                <div class="slider"></div>
                """
            step = if @query.getType(@facet.path) in ["int", "Integer"] then 1 else 0.1
            @round = round = (x) -> if step is 1 then Math.round(x) else x
            for prop, idx of {min: 0, max: 1} then do (prop, idx) =>
                @range.on "change:#{prop}", (m, val) =>
                    val = round(val)
                    @$("input.im-range-#{prop}").val "#{ val }"
                    if $slider.slider('values', idx) isnt val
                        $slider.slider('values', idx, val)
            @range.on 'change', () =>
                changed = @range.has('min') and @range.has('max') and (@range.get('min') > @min or @range.get('max') < @max)
                @$('.btn').toggleClass "disabled", !changed
                for prop, idx of {min: 0, max: 1}
                    unless @range.has(prop)
                        $slider.slider('values', idx, @[prop])
                        @$("input.im-range-#{prop}").val "#{ @[prop] }"
            $slider = @$('.slider').slider
                range: true
                min: @min
                max: @max
                values: [@min, @max]
                step: step
                slide: (e, ui) => @range.set min: ui.values[0], max: ui.values[1]
            @query.on 'range:selected', (from, upto) =>
                from = Math.min(from, @range.get('min')) if @range.has('min')
                upto = Math.max(upto, @range.get('max')) if @range.has('min')
                @range.set min: round(from), max: round(upto)
            @$('.btn-cancel').click => @range.clear()
            @$('.btn-primary').click =>
                @query.constraints = _(@query.constraints).filter (c) =>
                    c.path != @facet.path
                @query.addConstraints [
                    {
                        path: @facet.path
                        op: ">="
                        value: @range.get('min')
                    },
                    {
                        path: @facet.path
                        op: "<="
                        value: @range.get('max')
                    }
                ]

        moveRubberBand: (x) ->
            if @rubberBand.attr('x') is x and @rubberBand.attr('width') is 0
                @rubberBand.dragDir = null
            if @rubberBand? and (not @rubberBand.dragDir? or @rubberBand.dragDir is 'right')
                newWidth = x - @rubberBand.attr('x')
                if newWidth <= 0
                    @rubberBand.dragDir = null
                else
                    if @rubberBand.attr('x') < x
                        @rubberBand.dragDir = 'right'
                        @rubberBand.attr width: newWidth
                    if @rubberBand.attr('x') > x and @rubberBand.dragDir is 'right'
                        @rubberBand.attr width: newWidth
            if @rubberBand? and (not @rubberBand.dragDir? or @rubberBand.dragDir is 'left')
                if @rubberBand.attr('x') > x
                    @rubberBand.dragDir = 'left'
                    oldWidth = @rubberBand.attr('width')
                    oldX = @rubberBand.attr('x')
                    newWidth = oldWidth + (oldX - x)
                    @rubberBand.attr(x: x, width: newWidth) if newWidth > 0
                if @rubberBand.attr('x') < x and @rubberBand.dragDir is 'left'
                    oldWidth = @rubberBand.attr('width')
                    oldX = @rubberBand.attr('x')
                    newWidth = oldWidth - (x - oldX)
                    @rubberBand.attr(x: x, width: newWidth) if newWidth >= 0
                if newWidth < 0
                    @rubberBand.dragDir = null

        drawChart: (items) =>
            h = @chartHeight
            hh = h * 0.7
            max = _.max _.pluck items, "count"
            
            w = @$el.closest(':visible').width() * 0.95
            acceptableGap = Math.max (w / 15), "#{items[0].max}".split("").length * 5 * 1.5
            p = @paper
            gap = 0
            topMargin = h * 0.1
            leftMargin = 20
            stepWidth = (w - (leftMargin + 1)) / items[0].buckets
            baseLine = hh + topMargin

            for tick in [0 .. 10] then do (tick) ->
                line = p.path "M#{leftMargin - 4},#{baseLine - (hh / 10 * tick)} h#{w - gap}"
                line.node.setAttribute "class", "tickline"

            yaxis = @paper.path "M#{leftMargin - 4}, #{baseLine} v-#{hh}"
            yaxis.node.setAttribute "class", "yaxis"

            @rubberBand = null
            @selection = null

            @canvas.mousedown (e) =>
                x = e.offsetX
                @rubberBand = p.rect(x, 0, 10, h, 0)
                @rubberBand.attr fill: 'transparent', 'stroke-dasharray': '.'

            @canvas.mousemove (e) =>
                x = e.offsetX
                if @rubberBand?
                    @moveRubberBand(x)

            valForX = (x) =>
                if x <= leftMargin
                    return @min
                if x >= w
                    return @max
                conversionRate = (@max - @min) / (w - leftMargin)
                return @min + (conversionRate * x)

            xForVal = (val) =>
                if val is @min
                    return leftMargin
                if val is @max
                    return w
                conversionRate = (w - leftMargin) / (@max - @min)
                return leftMargin + (conversionRate * (val - @min))

            drawSelection = (x, width) =>
                @selection?.remove()
                @selection = p.rect(x, 0, width, h)
                @selection.node.setAttribute 'class', 'rubberband-selection'

            @canvas.mouseup (e) =>
                if @rubberBand?
                    min = valForX(@rubberBand.attr('x'))
                    max = valForX(@rubberBand.attr('x') + @rubberBand.attr('width'))
                    @range.set min: @round(min), max: @round(max)
                    @rubberBand.remove()
                @rubberBand = null

            @range.on 'change', () =>
                if @range.has('min') and @range.has('max')
                    x = xForVal(@range.get('min'))
                    width = xForVal(@range.get('max')) - x
                    drawSelection(x, width)
                else
                    @selection?.remove()
                    @selection = null
            
            for tick in [0, 5, 10] then do (tick) =>
                ypos = baseLine - (hh / 10 * tick)
                val = max / 10 * tick
                t = @paper.text(leftMargin - 6, ypos, val.toFixed()).attr
                    "text-anchor": "end"
                    "font-size": "10px"
                # Lord knows why?? Firefox does not need this... not needed in absolute...
                if $.browser.webkit
                    t.translate 0, -ypos unless @$el.offsetParent().filter( -> $(@).css("position") is "absolute").length

            for item, i in items then do (item, i) =>
                prop = item.count / max
                pathCmd = "M#{(item.bucket - 1) * stepWidth + leftMargin},#{baseLine} v-#{hh * prop} h#{stepWidth - gap} v#{hh * prop} z"
                path = @paper.path pathCmd
                width = (item.max - item.min) / item.buckets
                from = item.min + ((item.bucket - 1) * width)
                upto = item.min + ((item.bucket - 0) * width)
                path.click () =>
                    @query.trigger 'range:selected', from, upto

            item = items[0]
            fixity = if item.max - item.min > 5 then 0 else 2
            lastX = 0
            for xtick in [0 .. item.buckets]
                curX = xtick * stepWidth + leftMargin
                if lastX is 0 or curX - lastX >= acceptableGap or xtick is item.buckets
                    lastX = curX
                    val = item.min + (xtick * ((item.max - item.min) / item.buckets))
                    @paper.text(curX, baseLine + 5, val.toFixed(fixity))

            this

        _selecting_paths_: false

        drawCurve: () =>
            if @max is @min
                $(@el).remove()
                return
            sections = ((@max - @min) / @dev).toFixed()
            w = @$el.width()
            h = @chartHeight
            nc = NormalCurve(w / 2, w / sections)
            factor = h / nc(w / 2)
            invert = (x) -> h - x + 2
            scale = (x) -> x * factor
            f = _.compose invert, scale, nc
            xs = [1 .. w]
            points = _.zip xs, (f(x) for x in xs)
            pathCmd = "M1,#{ h }S#{ points.join(",") }L#{w - 1},#{ h }Z"

            # Draw the curve
            @paper.path(pathCmd)
            for stdevs in [0 .. ((sections/2) + 1)]
                xs = _.uniq([w / 2 - (stdevs * w / sections), w / 2 + (stdevs * w / sections)])

                getPathCmd = (x) -> "M#{x},#{h}L#{x},#{f(x)}"
                drawDivider = (x) => @paper.path(getPathCmd(x))
                drawDivider x for x in xs when ( 0 <= x <= w )


    exporting class PieFacet extends Backbone.View
        className: 'im-grouped-facet im-pie-facet im-facet'

        chartHeight: 100

        initialize: (@query, @facet, items, @hasMore, @filterTerm) ->
            @items = new Backbone.Collection(items)
            @items.each (item) -> item.set "visibility", true

            @items.maxCount = @items.first()?.get "count"
            @items.on "change:selected", =>
                someAreSelected = @items.any((item) -> item.get "selected")
                allAreSelected = !@items.any (item) -> not item.get "selected"
                @$('.im-filter .btn').attr "disabled", !someAreSelected
                @$('.im-filter .btn-toggle-selection').attr("disabled", allAreSelected)
                                                    .toggleClass("im-invert", someAreSelected)

        events:
            'click .im-filter .btn-primary': 'addConstraint'
            'click .im-filter .btn-cancel': 'resetOptions'
            'click .im-filter .btn-toggle-selection': 'toggleSelection'
            click: (e) ->
                e.stopPropagation()
                e.preventDefault()

        resetOptions: (e) ->
            @items.each (item) -> item.set "selected", false

        toggleSelection: (e) ->
            @items.each (item) -> item.set("selected", !item.get "selected") if item.get "visibility"

        addConstraint: (e) ->
            newCon = path: @facet.path
            vals = (item.get "item" for item in @items.filter (item) -> item.get "selected")
            if vals.length is 1
                if vals[0] is null
                    newCon.op = 'IS NULL'
                else
                    newCon.op = '='
                    newCon.value = "#{vals[0]}"
            else
                newCon.op = "ONE OF"
                newCon.values = vals
            newCon.title = @facet.title unless @facet.ignoreTitle
            @query.addConstraint newCon

        render: -> @addChart().addControls()

        @GREEKS = "αβγδεζηθικλμνξορστυφχψω".split("")

        addChart: ->
            return this if @items.all (i) -> i.get("count") is 1
            h = @chartHeight
            w = @$el.closest(':visible').width()
            r = h * 0.8 / 2
            chart = @make "div"
            @$el.append chart
            @paper = Raphael chart, w, h
            cx = w / 2
            cy = h / 2

            total = @items.reduce ((a, b) -> a + b.get "count"), 0
            degs = 0
            i = 0
            texts = @items.map (item) =>
                prop = item.get("count") / total
                item.set "percent", prop * 100
                rads = 2 * Math.PI * prop
                arc = if prop > 0.5 then 1 else 0
                dy = r + (-r * Math.cos rads)
                dx = r * Math.sin rads
                cmd = "M#{cx},#{cy} v-#{r} a#{r},#{r} 0 #{arc},1 #{dx},#{dy} z"
                path = @paper.path cmd
                item.set "path", path
                path.click () -> item.set selected: not item.get('selected')
                path.hover (() -> item.trigger 'hover'), (() -> item.trigger 'unhover')
                path.rotate degs, cx, cy
                textRads = (Raphael.rad degs) + (rads / 2)
                textdy = -(r * 0.6 * Math.cos textRads)
                textdx = r * 0.6 * Math.sin textRads
                item.set "symbol", PieFacet.GREEKS[i++]
                t = @paper.text cx, cy, item.get "symbol" #item.get "item"
                t.attr
                    "font-size": "14px"
                    "text-anchor": if textdx > 0 then "start" else "end"
                t.translate textdx, textdy
                # Lord knows why?? - not needed if in absolute...
                if $.browser.webkit
                    t.translate 0, -(r * 1.5) unless @$el.offsetParent().filter( -> $(@).css("position") is "absolute").length
                t.node.setAttribute "class", "pie-label"
                degs += 360 * prop
                t

            t.toFront() for t in texts
            this

        addControls: ->
            $grp = $("""
            <form class="form form-horizontal">
                <div class="input-prepend">
                    <span class="add-on"><i class="icon-refresh"></i></span><input type="text" class="input-medium search-query filter-values" placeholder="Filter values">
                </div>
                <div class="im-item-table">
                    <table class="table table-condensed">
                        <colgroup>
                            #{ @colClasses.map( (cl) -> "<col class=#{cl}>").join('') }
                        </colgroup>
                        <thead>
                            <tr>#{ @columnHeaders.map( (h) -> "<th>#{ h }</th>" ).join('') }</tr>
                        </thead>
                        <tbody class="scrollable"></tbody>
                    </table>
                </div>
            </form>""").appendTo @el
            $grp.button()
            @items.each (item) =>
                r = @makeRow item
                $grp.find('tbody').append r
            $grp.append """
                <div class="im-filter btn-group">
                    <button type="submit" class="btn btn-primary" disabled>Filter</button>
                    <button class="btn btn-cancel" disabled>Reset</button>
                    <button class="btn btn-toggle-selection"></button>
                </div>
            """
            xs = @items
            $valFilter = $grp.find(".filter-values")
            if @filterTerm
                $valFilter.val @filterTerm
            facet = @
            $valFilter.keyup (e) ->
                if facet.hasMore or (facet.filterTerm and $(@).val().length < facet.filterTerm.length)
                    _.delay (() -> facet.query.trigger('filter:summary', $valFilter.val())), 750
                else
                    pattern = new RegExp $(@).val(), "i"
                    xs.each (x) -> x.set "visibility", pattern.test x.get("item")
            $valFilter.prev().click (e) ->
                $(@).next().val(facet.filterTerm)
                xs.each (x) -> x.set "visibility", true

            this

        colClasses: ["im-item-selector", "im-item-value", "im-item-count", "im-prop-count"]

        columnHeaders: [' ', 'Item', 'Count', ' ']

        makeRow: (item) ->
            row = new FacetRow(item, @items)
            row.render().$el
            

    exporting class FacetRow extends Backbone.View

        tagName: "tr"
        className: "im-facet-row"

        isBelow: () ->
            parent = @$el.closest '.im-item-table'
            @$el.offset().top + @$el.outerHeight() > parent.offset().top + parent.outerHeight()

        isAbove: () ->
            parent = @$el.closest '.im-item-table'
            @$el.offset().top < parent.offset().top

        isVisible: () -> not (@isAbove() or @isBelow())

        initialize: (@item, @items) ->
            @item.on "change:selected", =>
                isSelected = @item.get "selected"
                if @item.has "path"
                    item.get("path").node.setAttribute "class", if isSelected then "selected" else ""
                @$el.toggleClass "active", isSelected
                if isSelected isnt @$('input').attr("checked")
                    @$('input').attr "checked", isSelected

            @item.on 'hover', =>
                @$el.addClass 'hover'
                unless @isVisible()
                    above = @isAbove()
                    surrogate = $ """
                        <div class="im-facet-surrogate #{ if above then 'above' else 'below'}">
                            <i class="icon-caret-#{ if above then 'up' else 'down' }"></i>
                            #{ @item.get('item') }: #{ @item.get('count') }
                        </div>
                    """
                    itemTable = @$el.closest('.im-item-table').append surrogate
                    newTop = if above
                        itemTable.offset().top + itemTable.scrollTop()
                    else
                        itemTable.scrollTop() + itemTable.offset().top + itemTable.outerHeight() - surrogate.outerHeight()
                    surrogate.offset top: newTop

            @item.on 'unhover', =>
                @$el.removeClass 'hover'
                s = @$el.closest('.im-item-table').find('.im-facet-surrogate').fadeOut 'fast', () ->
                    s.remove()

            @item.on "change:visibility", => @$el.toggle @item.get "visibility"

        events:
            'click': 'handleClick'
            'change input': 'handleChange'

        render: ->
            percent = (parseInt(@item.get("count")) / @items.maxCount * 100).toFixed()
            @$el.append """
                <td class="im-selector-col">
                    <span>#{ ((@item.get "symbol") || "") }</span>
                    <input type="checkbox">
                </td>
                <td class="im-item-col">#{@item.get "item"}</td>
                <td class="im-count-col">
                    <div class="im-facet-bar" style="width:#{percent}%">
                        #{@item.get "count"}
                    </div>
                </td>
            """
            if @item.get "percent"
                @$el.append """<td class="im-prop-col"><i>#{@item.get("percent").toFixed()}%</i></td>"""

            this

        handleClick: (e) ->
            e.stopPropagation()
            if e.target.type isnt 'checkbox'
                @$('input').trigger "click"

        handleChange: (e) ->
            e.stopPropagation()
            @item.set "selected", @$('input').is ':checked'

    exporting class HistoFacet extends PieFacet

        className: 'im-grouped-facet im-facet'

        chartHeight: 50

        colClasses: ["im-item-selector", "im-item-value", "im-item-count"]

        columnHeaders: [' ', 'Item', 'Count']
        
        addChart: ->
            h = @chartHeight
            hh = h * 0.8
            w = @$el.closest(':visible').width() * 0.95
            f = @items.first()
            max = f.get "count"
            return this if @items.all (i) -> i.get("count") is 1
            chart = @make "div"
            @$el.append chart
            p = @paper = Raphael chart, w, h
            gap = w * 0.01
            topMargin = h * 0.1
            leftMargin = 30
            stepWidth = (w - (leftMargin + 1)) / @items.size()
            baseline = hh + topMargin

            for tick in [0 .. 10] then do (tick) ->
                line = p.path "M#{leftMargin - 4},#{baseline -  (hh / 10 *  tick)} h#{w - gap}"
                line.node.setAttribute "class", "tickline"

            yaxis = @paper.path "M#{leftMargin - 4},#{baseline} v-#{hh}"
            yaxis.node.setAttribute "class", "yaxis"
            for tick in [0 .. 10] then do (tick) =>
                ypos = baseline - (hh / 10 * tick)
                val = max / 10 * tick
                unless val % 1
                    t = @paper.text(leftMargin - 6, ypos, val.toFixed()).attr
                        "text-anchor": "end"
                        "font-size": "10px"
                    # Lord knows why?? Firefox does not need this... not needed in absolute...
                    if $.browser.webkit
                        t.translate 0, -ypos unless @$el.offsetParent().filter( -> $(@).css("position") is "absolute").length


            @items.each (item, i) =>
                prop = item.get("count") / max
                pathCmd = "M#{i * stepWidth + leftMargin},#{baseline} v-#{hh * prop} h#{stepWidth - gap} v#{hh * prop} z"
                path = @paper.path pathCmd
                path.click () -> item.set selected: not item.get('selected')
                path.hover (() -> item.trigger 'hover'), (() -> item.trigger 'unhover')

                item.set "path", path

            this


    exporting class BooleanFacet extends NumericFacet
        handleSummary: (items) =>
            t = _(items).find (i) -> i.item is true
            f = _(items).find (i) -> i.item is false
            n = _(items).find (i) -> i.item is null
            total = (t?.count or 0) + (f?.count or 0) + (n?.count or 0)
            @drawChart total, (f?.count or 0)
            @drawControls total, (f?.count or 0)

        drawChart: (total, subtotal) =>
            h = 75
            w = @$el.closest(':visible').width()
            r = h * 0.8 / 2
            cx = w / 2
            cy = h / 2

            fprop = subtotal / total
            tprop = 1 - fprop

            if fprop is 0 or fprop is 1
                @paper.circle cx, cy, r
                t = @paper.text cx, cy, (if fprop is 1 then "false" else "true") + " (#{total})"
                t.attr
                    "font-size": "16px"
                return this

            degs = 0

            texts = (for prop, i in [fprop, tprop] then do (prop, i) =>
                rads = 2 * Math.PI * prop
                arc = if 0.5 < prop < 1 then 1 else 0
                dy = r + (-r * Math.cos rads)
                dx = r * Math.sin rads
                cmd = "M#{cx},#{cy} v-#{r} a#{r},#{r} 0 #{arc},1 #{dx},#{dy} z"
                path = @paper.path cmd
                if i is 0 then @fpath = path else @tpath = path
                path.rotate degs, cx, cy
                textRads = (Raphael.rad degs) + (rads / 2)
                textdy = -(r * 1.1 * Math.cos textRads)
                textdx = r * 1.1 * Math.sin textRads
                num = if i is 0 then subtotal else total - subtotal
                t = @paper.text cx, cy, """#{if i is 0 then "false" else "true"} (#{num})"""
                t.attr
                    "font-size": "12px"
                    "text-anchor": if textdx > 0 then "start" else "end"
                t.translate textdx, textdy
                # Lord knows why?? - not needed if in absolute...
                if $.browser.webkit
                    t.translate 0, -(r * 1.5) unless @$el.offsetParent().filter( -> $(@).css("position") is "absolute").length
                degs += 360 * prop
                t
            )
            t.toFront for t in texts
            this

        drawControls: (total, trues) =>
            return this unless @fpath and @tpath

            c = $(@container).append """
            <form class="form-inline">
                <div class="btn-group" data-toggle="buttons-radio">
                    <a href="#" class="btn im-trues">True</a>
                    <a href="#" class="btn im-falses">False</a>
                </div>
                <div class="pull-right im-filter">
                    <button class="btn btn-primary disabled">Filter</button>
                    <button class="btn btn-cancel disabled">Reset</button>
                </div>
            </form>
            """

            c.find('.btn-group').button()
             .find('.btn').click (e) => c.find('.im-filter .btn').removeClass "disabled"
                
            # TODO: move all this into events.
            c.find('.btn-cancel').click (e) =>
                @tpath.node.setAttribute("class", "trues")
                @fpath.node.setAttribute("class", "falses")
                c.find('.im-filter .btn').addClass "disabled"
                c.find('.btn').removeClass "active"
            c.find('.btn-primary').click (e) =>
                @query.addConstraint
                    path: @facet.path
                    op: '='
                    value: if c.find('.im-trues').is('.active') then "true" else "false"

            handleTheTruth = (selPath) => (e) =>
                @tpath.node.setAttribute("class", "")
                @fpath.node.setAttribute("class", "")
                selPath.node.setAttribute("class", "selected")
                $(e.target).button 'toggle'
                
            c.find('.im-trues').click handleTheTruth(@tpath)
            c.find('.im-falses').click handleTheTruth(@fpath)



