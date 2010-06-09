// javascript behaviors for the track configuration dialog

var TrackConfigure = Class.create({

   glyph_select: function(config_container,glyph_element) {

    var all = config_container.select('tr').findAll(function(a){return !a.hasClassName('general')});
    all.each(function(a){a.hide()});

    if (glyph_element.value.match(/xyplot/)){
       config_container.select('tr.xyplot').each(function(a){a.show()});
       this.pivot_select($('conf_bicolor_pivot'));
    }
    else if (glyph_element.value.match(/density/)){
       config_container.select('tr.density').each(function(a){a.show()});
       this.pivot_select($('conf_bicolor_pivot'));
    }
    else if (glyph_element.value.match(/whiskers/)){
       config_container.select('tr.whiskers').each(function(a){a.show()});
    }
    else {
       config_container.select('tr.features').each(function(a){a.show()});
    }
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
 }

});


var track_configure = new TrackConfigure;
