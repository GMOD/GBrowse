/*
 controller.js -- The GBrowse controller object

 Lincoln Stein <lincoln.stein@gmail.com>
 $Id: controller.js,v 1.13 2008-07-14 23:45:07 lstein Exp $

Indentation courtesy of Emacs javascript-mode 
(http://mihai.bazon.net/projects/emacs-javascript-mode/javascript.el)

*/

var GBrowseController = Class.create({

  initialize:
  function () {
    this.periodic_updaters        = new Array();
    this.track_images             = new Hash();
    this.segment_observers        = new Hash();
    this.update_on_load_observers = new Hash();
  },
  
  update_coordinates:
  function (action) {

    //Grey out image
    this.track_images.keys().each(
      function(image_id) {
	$(image_id).setOpacity(0.3);
      }
    );
    
    new Ajax.Request('#',{
      method:     'post',
      parameters: {navigate: action},
      onSuccess: function(transport) {
	var results                 = transport.responseJSON;
	var segment                 = results.segment;
	var track_keys              = results.track_keys;
	var overview_scale_bar_hash = results.overview_scale_bar;
	var detail_scale_bar_hash   = results.detail_scale_bar;

	Controller.update_scale_bar(overview_scale_bar_hash);
	Controller.update_scale_bar(detail_scale_bar_hash);

	Controller.segment_observers.keys().each(
	  function(e) {
	    $(e).fire('model:segmentChanged',
		      {segment:    segment, 
		       track_key:  track_keys[e]
		      });
	  });
      }
      
    });
  },

  register_track:
  function (detail_div_id,detail_image_id,track_type) {
    
    this.track_images.set(detail_image_id,1);
    if (track_type=="scale_bar"){
      return;
    }
    this.segment_observers.set(detail_div_id,1);
    this.update_on_load_observers.set(detail_div_id,1);

    $(detail_div_id).observe('model:segmentChanged',function(event) {
      var track_key = event.memo.track_key;
      if (track_key){
	if (Controller.periodic_updaters[detail_div_id]){
	  Controller.periodic_updaters[detail_div_id].stop();
	}
	
	track_image = document.getElementById(detail_image_id);
	Controller.periodic_updaters[detail_div_id] = 
	  new Ajax.PeriodicalUpdater(
	    detail_div_id,
	    '#',
	    { 
	      frequency:1, 
	      decay:1.5,
	      method: 'post',
	      parameters: {
		track_key:      track_key,
		retrieve_track: detail_div_id,
		image_width:    track_image.width,
		image_height:   track_image.height,
		image_id:       detail_image_id,
	      },
	      onSuccess: function(transport) {
		
		detail_div = document.getElementById(detail_div_id);
		if (transport.responseText.substring(0,18) == "<!-- AVAILABLE -->"){
		  detail_div.innerHTML = transport.responseText;
		  Controller.periodic_updaters[detail_div_id].stop();
		  Controller.reset_after_track_load();
		}
		else if (transport.responseText.substring(0,16) == "<!-- EXPIRED -->"){
		  Controller.periodic_updaters[detail_div_id].stop();
		  Controller.reset_after_track_load();
		}
		else {
		  var p_updater = Controller.periodic_updaters[detail_div_id];
		  var decay     = p_updater.decay;
		  p_updater.stop();
		  p_updater.decay = decay * p_updater.options.decay;
		  p_updater.timer = 
		    p_updater.start.bind(p_updater).delay(p_updater.decay 
							  * p_updater.frequency);
		}
	      }
	    }
	  );
      }
    }
      );
  },

  reset_after_track_load:
  // This may be a little overkill to run these after every track update but
  // since there is no "We're completely done with all the track updates for the
  // moment" hook, I don't know of another way to make sure the tracks become
  // draggable again
  function () {
    create_drag('overview_panels','track');
    create_drag('detail_panels','track');
  },
  
  update_scale_bar:
  function (bar_obj) {
    var image_id = bar_obj.image_id;
    $(image_id).src = bar_obj.url;
    $(image_id).height = bar_obj.height;
    $(image_id).width = bar_obj.width;
    $(image_id).setOpacity(1);
  },

  first_render:
  function()  {
    new Ajax.Request('#',{
      method:     'post',
      parameters: {first_render: 1},
      onSuccess: function(transport) {
	var results    = transport.responseJSON;
	var segment    = results.segment;
	var track_keys = results.track_keys;
	Controller.update_on_load_observers.keys().each(
	  function(e) {
	    $(e).fire('model:segmentChanged',
		      {segment:    segment, 
		       track_key:  track_keys[e]});
	  });
      }
    });
  }
});

var Controller = new GBrowseController; // singleton

function initialize_page() {
  //event handlers
  ['page_title','span'].each(function(el) {
    Controller.segment_observers.set(el,1);
    $(el).observe('model:segmentChanged',function(event) {
      new Ajax.Updater(this,'#',{
	parameters: {update: this.id}
      });
    }
      )
  });
  
  Controller.first_render();
}

