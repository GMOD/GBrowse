/*
 controller.js -- The GBrowse controller object

 Lincoln Stein <lincoln.stein@gmail.com>
 $Id: controller.js,v 1.22 2008-08-12 13:01:03 mwz444 Exp $

Indentation courtesy of Emacs javascript-mode 
(http://mihai.bazon.net/projects/emacs-javascript-mode/javascript.el)

*/

var GBrowseController = Class.create({

  initialize:
  function () {
    // periodic_updaters contains all the updaters for each track
    this.periodic_updaters        = new Array();
    this.track_images             = new Hash();
    this.segment_observers        = new Hash();
    this.update_on_load_observers = new Hash();
    // segment_info holds the information used in rubber.js
    this.segment_info;
    this.debug_status             = 'initialized';
  },
  
  update_coordinates:
  function (action) {

    this.debug_status             = 'updating coords';
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
        Controller.segment_info     = results.segment_info;
	    var track_keys              = results.track_keys;
	    var overview_scale_bar_hash = results.overview_scale_bar;
	    var region_scale_bar_hash   = results.region_scale_bar;
	    var detail_scale_bar_hash   = results.detail_scale_bar;
        Controller.debug_status     = 'updating coords - successful navigate';
    
	    Controller.update_scale_bar(overview_scale_bar_hash);
	    Controller.update_scale_bar(region_scale_bar_hash);
	    Controller.update_scale_bar(detail_scale_bar_hash);
    
	    Controller.segment_observers.keys().each(
	      function(e) {
	        $(e).fire('model:segmentChanged',
		      {
		        track_key:  track_keys[e]
		      });
          }
        ); //end each segment_observer
      } // end onSuccess
      
    }); // end Ajax.Request
    this.debug_status             = 'updating coords 2';
  }, // end update_coordinates

  register_track:
  function (track_div_id,track_image_id,track_type) {
    
    this.track_images.set(track_image_id,1);
    if (track_type=="scale_bar"){
      return;
    }
    this.segment_observers.set(track_div_id,1);
    this.update_on_load_observers.set(track_div_id,1);

    $(track_div_id).observe('model:segmentChanged',function(event) {
      var track_key = event.memo.track_key;
      if (track_key){
        if (Controller.periodic_updaters[track_div_id]){
          Controller.periodic_updaters[track_div_id].stop();
        }
    
        track_image = document.getElementById(track_image_id);
        Controller.periodic_updaters[track_div_id] = 
          new Ajax.PeriodicalUpdater( track_div_id, '#', { 
          frequency:1, 
          decay:1.5,
          method: 'post',
          parameters: {
            track_key:      track_key,
            retrieve_track: track_div_id,
            image_width:    track_image.width,
            image_height:   track_image.height,
            image_id:       track_image_id,
          },
          onSuccess: function(transport) {
          
            track_div = document.getElementById(track_div_id);
            if (transport.responseText.substring(0,18) == "<!-- AVAILABLE -->"){
              track_div.innerHTML = transport.responseText;
              Controller.periodic_updaters[track_div_id].stop();
              Controller.reset_after_track_load();
            }
            else if (transport.responseText.substring(0,16) == "<!-- EXPIRED -->"){
              track_div.innerHTML = transport.responseText;
              Controller.periodic_updaters[track_div_id].stop();
              Controller.reset_after_track_load();
            }
            else {
              var p_updater = Controller.periodic_updaters[track_div_id];
              var decay     = p_updater.decay;
              p_updater.stop();
              p_updater.decay = decay * p_updater.options.decay;
              p_updater.timer = 
              p_updater.start.bind(p_updater).delay(p_updater.decay 
                                * p_updater.frequency);
            }
          } // end onSuccess
        }); // end new Ajax.Periodical...
      } // end if (track_key)
    }); // end .observed
  }, // end register_track

  reset_after_track_load:
  // This may be a little overkill to run these after every track update but
  // since there is no "We're completely done with all the track updates for the
  // moment" hook, I don't know of another way to make sure the tracks become
  // draggable again
  function () {
    create_drag('overview_panels','track');
    create_drag('region_panels','track');
    create_drag('detail_panels','track');
  },
  
  update_scale_bar:
  function (bar_obj) {
    var image_id = bar_obj.image_id;
    var image = $(image_id);
    YAHOO.util.Dom.setStyle(image,'background', 'url('+bar_obj.url+') top left no-repeat');

    YAHOO.util.Dom.setStyle(image,'width', bar_obj.width+'px');
    YAHOO.util.Dom.setStyle(image,'height', bar_obj.height+'px');
    YAHOO.util.Dom.setStyle(image,'display','block');
    YAHOO.util.Dom.setStyle(image,'cursor','text');
    image.setOpacity(1);
  },

  first_render:
  function()  {
    this.debug_status             = 'first_render';
    new Ajax.Request('#',{
      method:     'post',
      parameters: {first_render: 1},
      onSuccess: function(transport) {
        var results    = transport.responseJSON;
        var track_keys = results.track_keys;
        Controller.segment_info = results.segment_info;

        Controller.update_on_load_observers.keys().each(
          function(e) {
            $(e).fire('model:segmentChanged',
              {
              track_key:  track_keys[e]});
          }
        );
        Controller.debug_status             = 'first_render finished';
      }
    });
    this.debug_status             = 'first_render part2';
  },

  add_track:
  function(track_name) {

    new Ajax.Request('#',{
      method:     'post',
      parameters: {
        add_track:  1,
        track_name: track_name,
      },
      onSuccess: function(transport) {
        var results    = transport.responseJSON;
        var track_data = results.track_data;
        for (var key in track_data){
          this_track_data    = track_data[key];
          var div_element_id = this_track_data.div_element_id;
          var html           = this_track_data.track_html;
          var panel_id       = this_track_data.panel_id;

          //Append new html to the appropriate section
          // This is a bit cludgy but we create a temp element, 
          // read the html into it and then move the div element 
          // back out.  This keeps the other tracks intact.
          var tmp_element       = document.createElement("tmp_element");
          tmp_element.innerHTML = html;
          $(panel_id).appendChild(tmp_element);
          $(panel_id).appendChild($(div_element_id));
          $(panel_id).removeChild(tmp_element);

          //Add New Track(s) to the list of observers and such
          Controller.register_track(div_element_id,this_track_data.image_element_id,'standard') ;

          //fire the segmentChanged for each track not finished
          if (html.substring(0,18) == "<!-- AVAILABLE -->"){
            Controller.reset_after_track_load();
          }
          else{
            $(div_element_id).fire('model:segmentChanged',
              { track_key:  this_track_data.track_key});
          }
        }
      },
    });
  },

  configure_plugin:
  function(div_id) {
    var plugin_configure_div  = $(div_id);
    var plugin_name  = document.pluginform.plugin.value;
    new Ajax.Updater(plugin_configure_div,'#',{
      parameters: {
        update: div_id,
        plugin_name: plugin_name,
      }
    });
  },

  reconfigure_plugin:
  function(plugin_name,plugin_action,div_id) {
    var plugin_configure_div  = $(div_id);
    var form_element = $("configure_plugin");
    new Ajax.Request('#',{
      method:     'post',
      parameters: form_element.serialize() +"&"+ $H({
            plugin_action: plugin_action,
            reconfigure_plugin: plugin_name
          }).toQueryString(),
      onSuccess: function(transport) {
        Controller.wipe_div(div_id); 
        // Need to update plugin tracks here
      } // end onSuccess
    });
  },

  wipe_div:
  function(div_id) {
    $(div_id).innerHTML = '';
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
  Overview.prototype.initialize();
  Region.prototype.initialize();
  Details.prototype.initialize();
}

