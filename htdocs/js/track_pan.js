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
				toCall(gbtrack);
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

		$('overview_marker').style.left = Math.round(this.overview_segment_start + this.overview_draggable_width * x) + 'px';
		$('region_marker').style.left   = Math.round(this.region_segment_start   + this.region_draggable_width   * x) + 'px';
	},

	// Creates the semi-transparent div that marks the current view on the overview track
	// If it already exists, updates its width based on the segment size
	create_overview_pos_marker:
	function() {
		if (!($('overview_marker'))) {
			$('Overview Scale_inner_div').parentNode.insert("<div id='overview_marker'></div>");
			$('overview_marker').setStyle({
				backgroundColor: this.marker_fill,
				position:        'absolute',
				top:             '0px',
				height:          '12px',
				opacity:         0.9  // Cross-browser opacity setter (from Prototype)
			});
			var nonDraggable = new Element('div');
			$('overview_marker').insert({top: nonDraggable});
			nonDraggable.setStyle({
				backgroundColor: this.marker_fill,
				borderLeft:      '1px solid ' + this.marker_outline,
				borderRight:     '1px solid ' + this.marker_outline,
				width:           '100%',
				height:          '100px',
				opacity:         0.5 
			});
			nonDraggable.style.pointerEvents = 'none'; // This lets the user click "through" the element, so
				// rubber dragging still works.  Prototype does not support setting this style yet, but
				// some browsers do: Firefox 3.6+, Safari 4.0+, and Chrome.

			if (this.details_mult > 1.0) {  //No need to be draggable if viewport is same size as loaded image
				$('overview_marker').setStyle({cursor: 'move'});

				new Draggable($('overview_marker'), {
					constraint: 'horizontal',
					zindex: 0, // defaults to 1000, which we don't want
					snap: function(x) {
						return[ (x > TrackPan.overview_segment_start) ? (x < (TrackPan.overview_segment_start + TrackPan.overview_draggable_width) ? x : (TrackPan.overview_segment_start + TrackPan.overview_draggable_width) ) : TrackPan.overview_segment_start ];
					},
					onDrag: function () { TrackPan.update_pan_position((parseInt($('overview_marker').style.left) - TrackPan.overview_segment_start) / TrackPan.overview_draggable_width) },
					onEnd:  function () { TrackPan.update_pan_position((parseInt($('overview_marker').style.left) - TrackPan.overview_segment_start) / TrackPan.overview_draggable_width) }
				});
			}
		}

		$('overview_marker').style.left  = this.overview_segment_start + 'px';
		$('overview_marker').style.width = Math.round(this.overview_segment_width/this.details_mult) - 2 + 'px';
	},

	// Creates the semi-transparent div that marks the current view on the region track
	// If it already exists, updates its width and position based on the segment and region sizes
	create_region_pos_marker:
	function() {
		if (!($('region_marker'))) {
			$('Region Scale_inner_div').parentNode.insert("<div id='region_marker'></div>");
			$('region_marker').setStyle({
				backgroundColor: this.marker_fill,
				position:        'absolute',
				top:             '0px',
				height:          '12px',
				opacity:         0.9  // Cross-browser opacity setter (from Prototype)
			});
			var nonDraggable = new Element('div');
			$('region_marker').insert({top: nonDraggable});
			nonDraggable.setStyle({
				backgroundColor: this.marker_fill,
				borderLeft:      '1px solid ' + this.marker_outline,
				borderRight:     '1px solid ' + this.marker_outline,
				width:           '100%',
				height:          '100px',
				opacity:         0.5 
			});
			nonDraggable.style.pointerEvents = 'none'; // This lets the user click "through" the element, so
				// rubber dragging still works.  Prototype does not support setting this style yet, but
				// some browsers do: Firefox 3.6+, Safari 4.0+, and Chrome.

			if (this.details_mult > 1.0) {  //No need to be draggable if viewport is same size as loaded image
				$('region_marker').setStyle({cursor: 'move'});

				new Draggable($('region_marker'), {
					constraint: 'horizontal',
					zindex: 0, // defaults to 1000, which we don't want
					snap: function(x) {
						return[ (x > TrackPan.region_segment_start) ? (x < (TrackPan.region_segment_start + TrackPan.region_draggable_width) ? x : (TrackPan.region_segment_start + TrackPan.region_draggable_width) ) : TrackPan.region_segment_start ];
					},
					onDrag: function () { TrackPan.update_pan_position((parseInt($('region_marker').style.left) - TrackPan.region_segment_start) / TrackPan.region_draggable_width) },
					onEnd:  function () { TrackPan.update_pan_position((parseInt($('region_marker').style.left) - TrackPan.region_segment_start) / TrackPan.region_draggable_width) }
		    		});
			}
		}
		$('region_marker').style.left  = this.region_segment_start + 'px';
		$('region_marker').style.width = Math.round(this.region_segment_width/this.details_mult) - 2 + 'px';
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
		this.marker_fill          = segment_info.hilite_fill;
		this.marker_outline       = segment_info.hilite_outline;
		this.flip                 = segment_info.flip;

		this.overview_segment_start  = Math.round(this.detail_start / this.overview_pixel_ratio + this.pad);          // # of pixels
		this.overview_segment_width  = Math.ceil((this.detail_stop - this.detail_start) / this.overview_pixel_ratio); //

		this.region_segment_start  = Math.round((this.detail_start - this.region_start) / this.region_pixel_ratio + this.pad); // # of pixels
		this.region_segment_width  = Math.ceil((this.detail_stop  - this.detail_start) / this.region_pixel_ratio);             //

		this.detail_draggable_width   = Math.ceil(this.detail_width - this.overview_width);
		this.overview_draggable_width = Math.ceil(this.overview_segment_width - this.overview_segment_width/this.details_mult);
		this.region_draggable_width   = Math.ceil(this.region_segment_width - this.region_segment_width/this.details_mult);

		this.viewable_segment_length = Math.round((this.detail_stop - this.detail_start) / this.details_mult);

		this.create_overview_pos_marker();
		this.create_region_pos_marker();

		if (this.details_mult <= 1.0) {
			this.x = 0;
			return; //No need to be draggable if viewport is same size as loaded image
		}

		this.each_details_track(function(gbtrack) {
			if (gbtrack.track_id == 'Detail Scale') {       // Special case for detail scale track - dragging it interferes with segment selection
				gbtrack.get_image_div().makePositioned();
				return;
			}
			new Draggable(gbtrack.get_image_div(), {
				constraint: 'horizontal',
				zindex: 0, // defaults to 1000, which we don't want because it covers labels
				snap:   function (x) { return[ (x < 0) ? ((x > -TrackPan.detail_draggable_width) ? x : -TrackPan.detail_draggable_width ) : 0 ]; },
				onDrag: function ()  { 
					if (TrackPan.flip) {
						TrackPan.update_pan_position(1 + parseInt(gbtrack.get_image_div().style.left) / TrackPan.detail_draggable_width);
					} else {
						TrackPan.update_pan_position(0 - parseInt(gbtrack.get_image_div().style.left) / TrackPan.detail_draggable_width);
					}
				},
				onEnd:  function ()  { 
					if (TrackPan.flip) {
						TrackPan.update_pan_position(1 + parseInt(gbtrack.get_image_div().style.left) / TrackPan.detail_draggable_width);
					} else {
						TrackPan.update_pan_position(0 - parseInt(gbtrack.get_image_div().style.left) / TrackPan.detail_draggable_width);
					}
				}
			});
		});

		this.update_pan_position(0.5); // start in the middle
	},

	//Similar to Controller scroll method
	scroll:
	function (direction,length_units) {
		var newPos = this.x;
		if (direction == 'right') {
			var new_stop = this.get_stop() + length_units * this.viewable_segment_length;
			if (new_stop > this.detail_stop + 10) { return false; }
			newPos += length_units/(this.details_mult-1);
		} if (direction == 'left') {
			var new_start = this.get_start() - length_units * this.viewable_segment_length;
			if (new_start < this.detail_start - 10) { return false; }
			newPos -= length_units/(this.details_mult-1);
		}
		this.update_pan_position(newPos);
		return true;
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


