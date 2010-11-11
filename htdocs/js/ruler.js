/*

 ruler.js -- GBrowse ruler

 $Id$ 

*/

var ruler_value = 0;

function createRuler () {
  $('ruler_handle').style.visibility = 'hidden';

  var half_handle_width = Math.round($('ruler_handle').getWidth()/2);
  var track_width  = $('ruler_track').getWidth();

  new Control.Slider('ruler_handle','ruler_track',{
    range: $R(half_handle_width, track_width-half_handle_width),
    onSlide: function (value) {
      ruler_value = value;
      updateRuler();
    }
  });
}

function toggleRuler (is_visible) {
   handle = $('ruler_handle');
   if (is_visible == false) {
      handle.style.visibility = 'hidden';
   } else {
      updateRuler();
      handle.style.visibility = 'visible';
   }
}

function updateRuler() {
  var height       = $('detail_panels').offsetHeight + 'px';
  var ruler_label  = $('ruler_label');
  var ruler_handle = $('ruler_handle');

  ruler_handle.style.height = height;

  var pad_left           = parseInt(Controller.segment_info.image_padding);
  var detail_pixel_ratio = parseFloat(Controller.segment_info.details_pixel_ratio);
  var flip               = Controller.segment_info.flip;

  var view_start = TrackPan.get_start() - pad_left * detail_pixel_ratio;
  var view_stop  = TrackPan.get_stop()  + pad_left * detail_pixel_ratio;

  var position = flip? Math.round(view_stop - ruler_value * detail_pixel_ratio)
                     : Math.round(view_start + ruler_value * detail_pixel_ratio);

  ruler_label.update(position);
}

