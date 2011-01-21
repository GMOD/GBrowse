/*

 track_pan.js -- The GBrowse track panning object

 $Id$ 

*/

var GBrowseTrackPan = Class.create({

	// Execute a method on each track in the "Details" section (including the scale track)
	each_details_track:
	function (toCall) {
		Controller.each_track(function(gbtrack) {
			if (gbtrack.track_type == 'standard' && gbtrack.track_section == 'detail' || gbtrack.track_id == 'Detail Scale') {
				if (gbtrack.get_image_div()) { // only worry about tracks that have loaded		
					toCall(gbtrack);
				}
			}
		});
	},

	// Given a value between 0 and 1, pans each track to that position.
	// x = 0: viewing the left end of the loaded segment
	// x = 1: viewing the right end of the loaded segment
	// 0 < x < 1: somewhere in the middle
	update_pan_position:
	function (x) {
		if      (x > 1) { x = 1; } // x must be between 0 and 1
		else if (x < 0) { x = 0; } // 

		this.x = x;

		var pos = Math.round(- x * this.detail_draggable_width);
		if (this.flip) {
			pos = - pos - this.detail_draggable_width;
		}
		pos += 'px';

		this.each_details_track(function(gbt) {
			gbt.get_image_div().style.left = pos;
		});

		if ($('overview_marker')) { $('overview_marker').style.left = 
			Math.round(this.overview_segment_start + this.overview_draggable_width * x) + 'px'; }
		if ($('region_marker'))   { $('region_marker').style.left   = 
			Math.round(this.region_segment_start   + this.region_draggable_width   * x) + 'px'; }

		updateRuler();

		if (this.get_start() > 0 && this.get_stop() > 0) {
			if (document.searchform) {
				document.searchform.name.value = this.ref + ':' + addCommas(this.get_start()) + '..' + addCommas(this.get_stop());
			}

			var page_title = this.description + ': ' + Controller.translate('SHOWING_FROM_TO',
					    this.length_label, this.ref, addCommas(this.get_start()), addCommas(this.get_stop()));
			document.title = page_title;
			$('page_title').update(page_title);
		} 
	},

	// Creates the semi-transparent div that marks the current view on the overview track
	// If it already exists, updates its width based on the segment size
	create_overview_pos_marker:
	function() {
	    if (!($('overview_panels'))) { return; }

	    if (!($('overview_marker'))) {
		$('overview_panels').insert("<div id='overview_marker'></div>");
		$('overview_marker').setStyle({
			backgroundColor: this.marker_fill,
			    position:        'absolute',
			    top:             '0px',
			    borderLeft:      '1px solid ' + this.marker_outline,
			    borderRight:     '1px solid ' + this.marker_outline,
			    height:          '400px',
			    cursor:          'text',
			    zIndex:          5
			    });
		$('overview_marker').onmousedown = Overview.prototype.startSelection; // Rubber band selection
	    }
	    $('overview_marker').setOpacity(0.55);
	    if (this.details_mult > 1.0) {
		var drag_handle = new Element('div');
		$('overview_marker').innerHTML = '';
		$('overview_marker').insert({top: drag_handle});
		drag_handle.setStyle({
			backgroundColor: this.marker_outline,
			    width:           '100%',
			    height:          '12px',
			    opacity:         0.6  // Cross-browser opacity setter (from Prototype)
			    });

		if (this.details_mult > 1.0) {  //No need to be draggable if viewport is same size as loaded image
		    drag_handle.setStyle({cursor: 'move'});
		    this.overview_draggable = new Draggable($('overview_marker'), {
		    	    constraint: 'horizontal',
		     	    snap: function(x) {
		     	    	return[ (x > TrackPan.overview_segment_start) ? (x < (TrackPan.overview_segment_start + TrackPan.overview_draggable_width) ? x : (TrackPan.overview_segment_start + TrackPan.overview_draggable_width) ) : TrackPan.overview_segment_start ];
		     	    },
		     	    handle: drag_handle,
		     	    onDrag: function () { 
			    	TrackPan.update_pan_position((parseInt($('overview_marker').style.left) 
			    				      - TrackPan.overview_segment_start) / TrackPan.overview_draggable_width) },
		     	    onEnd:  function () { 
			    	TrackPan.update_pan_position((parseInt($('overview_marker').style.left) 
			    				      - TrackPan.overview_segment_start) / TrackPan.overview_draggable_width) }
		     	});
		}
	    } else {
		//No need to be draggable if viewport is same size as loaded image
		if (this.overview_draggable) { this.overview_draggable.destroy(); }
		$('overview_marker').innerHTML = '';
	    }
	    
	    $('overview_marker').style.left  = this.overview_segment_start + 'px';
	    var width = Math.round(this.overview_segment_width/this.details_mult) - 2;
	    if (width < 1) {
		width = 1;
	    }
	    $('overview_marker').style.width = width + 'px';
	},

	// Creates the semi-transparent div that marks the current view on the region track
	// If it already exists, updates its width and position based on the segment and region sizes
	create_region_pos_marker:
	function() {
		if (!($('region_panels'))) { return; }

		if (!($('region_marker'))) {
			$('region_panels').insert("<div id='region_marker'></div>");
			$('region_marker').setStyle({
				backgroundColor: this.marker_fill,
				position:        'absolute',
				top:             '0px',
				borderLeft:      '1px solid ' + this.marker_outline,
				borderRight:     '1px solid ' + this.marker_outline,
				height:          '400px',
				cursor:          'text',
				zIndex:          5
			});
			$('region_marker').onmousedown = Region.prototype.startSelection; // Rubber band selection
		}
		$('region_marker').setOpacity(0.55);
		if (this.details_mult > 1.0) {
			var drag_handle = new Element('div');
			$('region_marker').innerHTML = '';
			$('region_marker').insert({top: drag_handle});
			drag_handle.setStyle({
				backgroundColor: this.marker_outline,
				width:           '100%',
				height:          '12px',
				opacity:         0.6  // Cross-browser opacity setter (from Prototype)
			});

			drag_handle.setStyle({cursor: 'move'});

			this.region_draggable = new Draggable($('region_marker'), {
				constraint: 'horizontal',
				snap: function(x) {
					return[ (x > TrackPan.region_segment_start) ? (x < (TrackPan.region_segment_start + TrackPan.region_draggable_width) ? x : (TrackPan.region_segment_start + TrackPan.region_draggable_width) ) : TrackPan.region_segment_start ];
				},
				handle: drag_handle,
				onDrag: function () { TrackPan.update_pan_position((parseInt($('region_marker').style.left) - TrackPan.region_segment_start) / TrackPan.region_draggable_width) },
				onEnd:  function () { TrackPan.update_pan_position((parseInt($('region_marker').style.left) - TrackPan.region_segment_start) / TrackPan.region_draggable_width) }
	    		});
		} else if (this.details_mult <= 1.0) {
			//No need to be draggable if viewport is same size as loaded image
			if (this.region_draggable) { this.region_draggable.destroy(); }
			$('region_marker').innerHTML = '';
		}

		$('region_marker').style.left  = this.region_segment_start + 'px';
		var width = Math.round(this.region_segment_width/this.details_mult) - 2;
		if (width < 1) {
			width = 1;
		}
		$('region_marker').style.width = width + 'px';
	},

	grey_out_markers:
	function () {
		if ($('overview_marker')) { $('overview_marker').setOpacity(0.2); }
		if ($('region_marker'))   { $('region_marker').setOpacity(0.2); }
	},

	make_track_draggable:
	function (gbtrack) {
		if (gbtrack.track_id == 'Detail Scale') {       // Special case for detail scale track - dragging it interferes with segment selection
			gbtrack.get_image_div().makePositioned();
			return;
		}
		if (!Prototype.Browser.IE)
		    gbtrack.get_image_div().setStyle({cursor: 'url('+Controller.button_url('cursor-ewmove.cur')+'), move'});
		new Draggable(gbtrack.get_image_div(), {
			constraint: 'horizontal',
			zindex: 0, // defaults to 1000, which we don't want because it covers labels
			starteffect: false,
			endeffect: false,
			snap:   function (x) { return[ (x < 0) ? ((x > -TrackPan.detail_draggable_width) ? x : -TrackPan.detail_draggable_width ) : 0 ]; },
			onDrag: function ()  { 
				if (TrackPan.flip) {
					TrackPan.update_pan_position(1 + 
								     parseInt(gbtrack.get_image_div().style.left) / TrackPan.detail_draggable_width);
				} else {
					TrackPan.update_pan_position(0 - 
								     parseInt(gbtrack.get_image_div().style.left) / TrackPan.detail_draggable_width);
				}
			},
			onEnd:  function ()  { 
				if (TrackPan.flip) {
					TrackPan.update_pan_position(1 + 
								     parseInt(gbtrack.get_image_div().style.left) / TrackPan.detail_draggable_width);
				} else {
					TrackPan.update_pan_position(0 - 
								     parseInt(gbtrack.get_image_div().style.left) / TrackPan.detail_draggable_width);
				}
			}
		    });
	},

	// Called by controller when the loaded tracks may have changed. Makes sure all tracks are draggable, and 
	// updates new tracks to the correct position.
	update_draggables:
	function () {
		if (this.details_mult > 1) {
			this.each_details_track(TrackPan.make_track_draggable);
			this.update_pan_position(this.x);
		}
	},


	// Sets up each details track so that they can be dragged left and right. Also calls helper methods to set up
	// position markers, etc. This should be called any time the segment changes or when a new track is loaded
	make_details_draggable:
	function () {
		var segment_info          = Controller.segment_info;
		this.details_mult         = parseFloat(segment_info.details_mult);
		this.detail_width         = parseInt(segment_info.detail_width);
		this.overview_width       = parseInt(segment_info.overview_width);
		this.region_width         = parseInt(segment_info.region_width);
		this.region_start         = parseInt(segment_info.region_start);
		this.pad                  = parseInt(segment_info.image_padding);
		this.detail_start         = parseInt(segment_info.detail_start);
		this.detail_stop          = parseInt(segment_info.detail_stop);
		this.overview_pixel_ratio = parseFloat(segment_info.overview_pixel_ratio);
		this.region_pixel_ratio   = parseFloat(segment_info.region_pixel_ratio);
		this.ref                  = segment_info.ref;
		this.description          = segment_info.description;
		this.length_label         = segment_info.length_label;
		this.marker_fill          = segment_info.hilite_fill;
		this.marker_outline       = segment_info.hilite_outline;
		this.flip                 = segment_info.flip;
		this.initial_view_start   = parseInt(segment_info.initial_view_start);
		this.initial_view_stop    = parseInt(segment_info.initial_view_stop);
		this.width_no_pad         = parseInt(segment_info.width_no_pad);

		this.overview_segment_start   = Math.round(this.detail_start / this.overview_pixel_ratio + this.pad);          // # of pixels
		this.overview_segment_width   = Math.ceil((this.detail_stop - this.detail_start) / this.overview_pixel_ratio); //

		this.region_segment_start     = Math.round((this.detail_start - this.region_start) / this.region_pixel_ratio + this.pad); // # of pixels
		this.region_segment_width     = Math.ceil((this.detail_stop  - this.detail_start) / this.region_pixel_ratio);             //

		this.detail_draggable_width   = Math.ceil(this.detail_width - this.overview_width);
		this.overview_draggable_width = Math.ceil(this.overview_segment_width - this.overview_segment_width/this.details_mult);
		this.region_draggable_width   = Math.ceil(this.region_segment_width - this.region_segment_width/this.details_mult);

		this.viewable_segment_length  = Math.round((this.detail_stop - this.detail_start) / this.details_mult);

		this.create_overview_pos_marker();
		this.create_region_pos_marker();

		if (this.details_mult <= 1.0) {
			this.x = 0;

			this.each_details_track(function(gbtrack) {
				gbtrack.get_image_div().setStyle({left:'0px'});
			});

			return; //No need to be draggable if viewport is same size as loaded image
		}

		this.each_details_track(TrackPan.make_track_draggable);
		
		var scroll_to = 0.5; // start in the middle (by default)
		if (this.initial_view_start >= 0) {
			scroll_to = this.position_from_start(this.initial_view_start);
		}
		this.update_pan_position(scroll_to); 
	},

	scroll:
	function (direction,length_units) {
		var newPos = this.x;
		if (direction == 'right') {
			var new_stop = this.get_stop() + length_units * this.viewable_segment_length;
			if (new_stop > this.detail_stop + this.viewable_segment_length*0.1) { return false; }
			newPos += length_units/(this.details_mult-1);
		} if (direction == 'left') {
			var new_start = this.get_start() - length_units * this.viewable_segment_length;
			if (new_start < this.detail_start - this.viewable_segment_length*0.1) { return false; }
			newPos -= length_units/(this.details_mult-1);
		}
		this.update_pan_position(newPos);
		return true;
	},

	position_from_start:
	function(start) {
		var scrollable_segment_length = this.viewable_segment_length * (this.details_mult - 1);
		var coord = (start - this.detail_start)  / scrollable_segment_length;
		return coord;
	},

	get_start:
	function () {
		var len = this.detail_stop - this.detail_start;
		var start = Math.round(this.detail_start + len * (this.details_mult - 1) / this.details_mult * this.x);
		return start;
	},

	get_stop:
	function () {
		var len = this.detail_stop - this.detail_start;
		var start = Math.round(this.detail_start + len * (this.details_mult - 1) / this.details_mult * this.x);
		var stop = start + Math.round(len/this.details_mult);
		return stop;
	}

});

var TrackPan = new GBrowseTrackPan; // Just make one copy of the object. Controller accesses it through this name

Event.observe(window, 'load', function() {
	if (!document.activeElement) {
		return; // only allow keyboard panning for browsers that support document.activeElement
	}

	Event.observe(document, (Prototype.Browser.WebKit)? 'keydown' : 'keypress', function(e) { 
		if (document.activeElement.tagName == 'INPUT' || document.activeElement.tagName == 'TEXTAREA')
			return;

		var code;
		if (!e)
			var e = window.event;
		if (e.keyCode)
			code = e.keyCode;
		else if (e.which)
			code = e.which;

		if (code == 37)
			TrackPan.scroll("left", 0.15);
		else if (code == 39)
			TrackPan.scroll("right", 0.15);
	});
});

function addCommas(number)
{
	number += '';
	var x = number.split('.');
	var whole_part = x[0];
	var decimal_part = x.length > 1 ? '.' + x[1] : '';
	var regex = /(\d+)(\d{3})/;
	while (regex.test(whole_part)) {
		whole_part = whole_part.replace(regex, '$1' + ',' + '$2');
	}
	return whole_part + decimal_part;
}

