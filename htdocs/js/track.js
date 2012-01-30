/*
 track.js -- The GBrowse track object

 Ben Faga <faga.cshl@gmail.com>
 $Id$

Method structure
 - Class Utility Methods

*/

var GBrowseTrack = Class.create({

  // Class Utility Methods ******************************************
  
  initialize:
  function (track_id,track_name,track_type,track_section) {
    this.track_id        = track_id;
    this.track_name      = track_name;
    this.track_type      = track_type;
    this.track_section   = track_section;
    this.track_div_id    = "track_"+track_id;
    this.track_image_id  = track_id + "_image";
    this.last_update_key = 0;
    this.expired_count   = 0;
//  alert(track_section);
    if (track_type == 'scale_bar') {
      this.standard_track  = false;
    }
    else {
      this.standard_track = true;
    }

  },

  set_last_update_key:
  function (time_key) {
    this.last_update_key = time_key;
   
  },

  get_last_update_key:
  function () {
    return this.last_update_key;
  },

  get_image_div:
  function () {
    return $(this.track_id+'_inner_div');
  },

  is_standard_track:
  function () {
    return this.standard_track;
  },

  increment_expired_count:
  function () {
    this.expired_count = this.expired_count + 1;
  },

  // Tell the track that it has been resolved.
  track_resolved:
  function () {
    this.expired_count = 0;
  }

});


