// javascript behaviors for the track configuration dialog

var TrackConfigure = Class.create({

   glyph_select: function(config_container,glyph_element) {

    if (glyph_element == null) return;

    var graphtype = $('conf_'+glyph_element.value+'_graphtype_id');
    var subtype   = $('conf_'+glyph_element.value+'_subtype_id');

    var all = config_container.select('tr').findAll(function(a){return !a.hasClassName('general')});
    all.each(function(a){a.hide()});
    var specific = false;

    if (glyph_element.value.match(/xyplot/)) {
       config_container.select('tr.xyplot').each(function(a){a.show()});
       specific = true;
    }
    if (glyph_element.value.match(/whiskers/)){
	config_container.select('tr.whiskers').each(function(a){a.show()});
	specific = true;
    }
    if (glyph_element.value.match(/vista/)) {
       config_container.select('tr.vista_plot').each(function(a){a.show()});
       if (subtype.value.match(/signal/)) {
	   this.adjust_height(40,200);
	   if (graphtype.value.match(/whiskers/))
	       config_container.select('tr.whiskers').each(function(a){a.show()});
	   else {
	      config_container.select('tr.xyplot').each(function(a){a.show()});
	      config_container.select('tr.wiggle').each(function(a){a.show()});
	   }
	   if (subtype.value.match(/peaks/))
	       config_container.select('tr.peaks').each(function(a){a.show()});
       } else if (subtype.value.match(/density/)) {
	   this.adjust_height(5,30);
	   config_container.select('tr.density').each(function(a){a.show()});
       } else if (subtype.value.match(/peaks/)) {
	   config_container.select('tr.peaks').each(function(a){a.show()});
       } else {
	   config_container.select('tr.graphtype').each(function(a){a.hide()});
       }
       specific = true;
    }
    if (glyph_element.value.match(/density/)){
       config_container.select('tr.density').each(function(a){a.show()});
       this.adjust_height(5,30);
       specific = true;
    }
    if (glyph_element.value.match(/wiggle/)){
       config_container.select('tr.wiggle').each(function(a){a.show()});
       var x = $('conf_xyplot_subtype');
       if (x != null) x.hide();
       specific = true;
    }
    if (glyph_element.value.match(/xyplot|whiskers/)) {
       this.adjust_height(40,200);
    }
    if (!specific) {
       config_container.select('tr.features').each(function(a){a.show()});
    }

    config_container.select('tr.'+glyph_element.value).each(function(a){a.show()});

    var signal = glyph_element.value.match(/xyplot|density|wiggle/)
                 || (glyph_element.value.match(/vista/) && subtype.value.match(/signal/));
    var can_pivot = !(glyph_element.value.match(/whiskers/) || (graphtype !=null && graphtype.value.match(/whiskers/)));
    can_pivot     = can_pivot || (glyph_element.value.match(/vista/) && subtype.value.match(/density/));
    if (can_pivot) {
	this.pivot_select($('conf_bicolor_pivot'));
    }
    if (signal) {
       if (glyph_element.value.match(/wiggle|vista/))
	   this.autoscale_select($('conf_wiggle_autoscale'),glyph_element);
       else      
	   this.autoscale_select($('conf_xyplot_autoscale'),glyph_element);
    } else {
	config_container.select('tr.graphtype').each(function(a){a.hide()});
	config_container.select('tr.autoscale').each(function(a){a.hide()});
    }
 },

 adjust_opacity: function(option) {
   if (option == 4)
       $('opacity').show();
   else
       $('opacity').hide();
 },

 adjust_format: function(el) {
   var option = el.value;
   this.adjust_opacity(option);
   if (option == 4) {
       this.set_autocolors(true);
   }
   else {
       this.set_autocolors(false);
   }
 },

 set_autoscale: function(el) {
    if (el.value != 'none')
	$$('input.score_bounds').each(function(a){a.value=''});
 },

 set_autocolors: function(flag) {
            $('conf_color_series').checked=flag;
	    if (flag) {
		$$('select.color_picker').each(function(a){a.disable()});
		$$('tr.color_picker').each(function(a){a.style.opacity=0.5});
	    } else {
		$$('select.color_picker').each(function(a){a.enable()});
		$$('tr.color_picker').each(function(a){a.style.opacity=1.0});
	    }
	    this.glyph_select($('config_table'),$('glyph_picker_id'));
 },

 set_minmax: function(el) { 
	$F('autoscale_popup').selectedIndex=0;   
 },

 adjust_height: function(min,max) {
    var el = $('conf_height');
    if (el==null) return;
    var current = el.value;
    var options = el.options;
    if (current < min) {
	for (var i=0;i<options.length;i++) {
	    if (options[i].value >= min) {
		el.value = options[i].value;
		return;
	    }
	}
    }
    else if (current > max) {
	for (var i=options.length-1;i>0;i--) {
	    if (options[i].value <= max) {
		el.value = options[i].value;
		return;
	    }
	}
    }
 },

 autoscale_select: function(scale_element,glyph_element) {
   var v=scale_element.value;
   var g=glyph_element.value;

   var autoscales = $('config_table').select('tr').findAll(function(a){return a.hasClassName('autoscale')});
   autoscales.each(function(a){a.hide()});
   if (g.match(/wiggle/) || g.match(/vista/)) {
       $('wiggle_autoscale').show();
   }
   else if (g.match(/xyplot/) || g.match(/density/)) {
       $('xyplot_autoscale').show();
   }

   var e=$('fixed_minmax');
   if (v=='none') {e.show()} else {e.hide()};

   var f=$('wiggle_z_fold');
   if (v=='z_score' || v=='clipped_global') {f.show()} else {f.hide()};
 },

 pivot_select: function(pivot_element) {
   var e=$('switch_point_other');
   var f=$$('tr.switch_point_color');
   if (pivot_element.value=='value'){
      e.show()
   } else{
      e.hide();
   }
   if (pivot_element.value=='none') {
      f.each(function(a){a.hide()});
      $('bgcolor_picker').show();
   } else {
     f.each(function(a){a.show()});
     $('bgcolor_picker').hide();
   }
  },


 set_opacity: function (opacity) {
	    var num = new Number(opacity);
	    if (isNaN(num)) num=0.5;
	    if (num > 1.0) num=1.0;
	    if (num < 0.0) num=0.0;
	    var thumb = $('opacity_thumb');
	    var right = $('opacity_box').getDimensions().width-thumb.getDimensions().width;    
	    thumb.style.left = num*right + 'px';
	    $$('img.opacity').each(function (e) {e.setOpacity(num)});
	    $('opacity_value').value=num.toFixed(2);
	},

 init: function (opacity) {
	    new Draggable('opacity_thumb',
                          {constraint:'horizontal',
			   snap: function(x,y,draggable) {
				  var parentDimensions = draggable.element.parentNode.getDimensions();
				  var left = 0;
				  var right=parentDimensions.width-draggable.element.getDimensions().width;
				  if (x < left)  x = left;
				  if (x > right) x = right;
				  return [x,y];
			      },
			   change: function(draggable) {
				  var el    = draggable.element;
				  var right = draggable.element.parentNode.getDimensions().width-el.getDimensions().width;
				  var percent = el.offsetLeft/right;
				  track_configure.set_opacity(percent);
			      }
			  }
			  );
	    this.set_opacity(opacity);
	    $('opacity_value').observe('change',function() {track_configure.set_opacity(this.value)});
	    $('format_option').observe('change',function() {track_configure.adjust_format(this)});
	    $('conf_color_series').observe('change',function() {track_configure.set_autocolors(this.checked)});
	    this.glyph_select($('config_table'),$('glyph_picker_id'));
	    this.adjust_opacity($('format_option').value);
	    this.set_autocolors($('conf_color_series').checked);
	}
});


var track_configure = new TrackConfigure;

