/*
 track.js -- The GBrowse track object

 Ben Faga <faga.cshl@gmail.com>
 $Id: track.js,v 1.3 2008-09-29 15:09:38 mwz444 Exp $

Method structure
 - Class Utility Methods

*/

var GBrowseTrack = Class.create({

  // Class Utility Methods ******************************************
  
  initialize:
  function (track_name,track_type) {

    this.track_name      = track_name;
    this.track_div_id    = "track_"+track_name;
    this.track_image_id  = track_name + "_image";
    this.track_type      = track_type;
    this.last_update_key = 0;

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

  is_standard_track:
  function () {
    return this.standard_track;
  }

});


