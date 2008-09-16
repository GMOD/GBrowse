/*
 track.js -- The GBrowse track object

 Ben Faga <faga.cshl@gmail.com>
 $Id: track.js,v 1.1 2008-09-16 17:34:03 mwz444 Exp $

Method structure
 - Class Utility Methods

*/

var GBrowseTrack = Class.create({

  // Class Utility Methods ******************************************
  
  initialize:
  function (track_name,track_type) {

    this.track_name     = track_name;
    this.track_div_id   = "track_"+track_name;
    this.track_image_id = track_name + "_image";
    this.track_type     = track_type;

  },

});


