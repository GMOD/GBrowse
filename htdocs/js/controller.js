/*
 controller.js -- The GBrowse controller object

 Lincoln Stein <lincoln.stein@gmail.com>
 $Id: controller.js,v 1.34 2008-08-25 20:45:02 mwz444 Exp $

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
    this.retrieve_tracks          = new Hash();
    // segment_info holds the information used in rubber.js
    this.segment_info;
    this.debug_status             = 'initialized';
  },
  
  update_coordinates:
  function (action) {

    // submit search form if the detail panel doesn't exist
    if ( null == $('detail_panels') ){
        document.searchform.force_submit.value = 1; 
        document.searchform.submit(); 
    }

    this.debug_status             = 'updating coords';
    //Grey out image
    this.track_images.values().each(
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
    
        if (overview_scale_bar_hash){
          Controller.update_scale_bar(overview_scale_bar_hash);
        }
        if (region_scale_bar_hash){
          Controller.update_scale_bar(region_scale_bar_hash);
        }
        if (detail_scale_bar_hash){
          Controller.update_scale_bar(detail_scale_bar_hash);
        }
    
	    Controller.segment_observers.keys().each(
	      function(e) {
	        $(e).fire('model:segmentChanged',
		      {
		        track_key:  track_keys[e]
		      });
          }
        ); //end each segment_observer
        Controller.get_multiple_tracks(track_keys);
      } // end onSuccess
      
    }); // end Ajax.Request
    this.debug_status             = 'updating coords 2';
  }, // end update_coordinates

  get_multiple_tracks:
  function (track_keys) {
    
    this.retrieve_tracks.keys().each(
      function(track_div_id) {
        Controller.retrieve_tracks.set(track_div_id,true);
      }
    );

    this.get_remaining_tracks(track_keys,1000,1.5);
  },

  get_remaining_tracks:
  function (track_keys,time_out,decay){

    var track_div_ids = [];
    var finished = true;
    var track_key_str = '';
    this.retrieve_tracks.keys().each(
      function(track_div_id) {
        if(Controller.retrieve_tracks.get(track_div_id)){
            track_div_ids.push(track_div_id);
            track_key_str += '&tk_'+track_div_id+"="+track_keys[track_div_id];
            finished = false;
        }
      }
    );

    if (finished){
      return;
    }

    new Ajax.Request('#',{
      method:     'post',
      parameters: $H({ retrieve_multiple: 1, track_div_ids: track_div_ids, }).toQueryString() + track_key_str,
      onSuccess: function(transport) {
        var continue_requesting = false;
        var results    = transport.responseJSON;
        var track_html_hash = results.track_html;
        for (var track_div_id in track_html_hash){
          track_html    = track_html_hash[track_div_id];

          track_div = document.getElementById(track_div_id);
          if (track_html.substring(0,18) == "<!-- AVAILABLE -->"){
            track_div.innerHTML = track_html;
            Controller.retrieve_tracks.set(track_div_id,false);
          }
          else if (track_html.substring(0,16) == "<!-- EXPIRED -->"){
               $(this.track_image_id[track_div_id]).setOpacity(0);
          }
          else {
            continue_requesting = true;
          }
        }
        Controller.reset_after_track_load();
        if (continue_requesting){
          setTimeout( function() {
            Controller.get_remaining_tracks(track_keys,time_out*decay,decay)
          } ,time_out);
        }
      }, // end onSuccess
    }); // end new Ajax.Request

  }, // end get_remaining_tracks

  register_track:
  function (track_div_id,track_image_id,track_type) {
    
    this.track_images.set(track_div_id,track_image_id);
    if (track_type=="scale_bar"){
      return;
    }
    this.retrieve_tracks.set(track_div_id,true);
  }, // end register_track

  reset_after_track_load:
  // This may be a little overkill to run these after every track update but
  // since there is no "We're completely done with all the track updates for the
  // moment" hook, I don't know of another way to make sure the tracks become
  // draggable again
  function () {
    if ( null != $('overview_panels') ){
      create_drag('overview_panels','track');
    }
    if ( null != $('region_panels') ){
      create_drag('region_panels','track');
    }
    if ( null != $('detail_panels') ){
      create_drag('detail_panels','track');
    }
  },
  
  update_scale_bar:
  function (bar_obj) {
    var image_id = bar_obj.image_id;
    var image = $(image_id);
    image.setStyle({
        background: "url(" + bar_obj.url + ") top left no-repeat",
        width:      bar_obj.width+'px',
        height:     bar_obj.height+'px',
        display:    'block',
        cursor:     'text',
    });
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

        Controller.get_multiple_tracks(track_keys);

        Controller.debug_status             = 'first_render finished';
      }
    });
    this.debug_status             = 'first_render part2';
  },

  add_track:
  function(track_name) {

    if ( null != $('track_'+track_name)){
      return;
    }

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
            var track_keys = new Array();
            track_keys[div_element_id]=this_track_data.track_key;
            Controller.retrieve_tracks.set(div_element_id,true);
            Controller.get_remaining_tracks(track_keys,1000,1.5);
          }
        }
      },
    });
  },

  rerender_track:
  function(track_name,track_div_id) {

    var image_id = this.track_images.get(track_div_id);
    $(image_id).setOpacity(0.3);
    new Ajax.Request('#',{
      method:     'post',
      parameters: {
        rerender_track:  1,
        track_name: track_name,
      },
      onSuccess: function(transport) {
        var results    = transport.responseJSON;
        var track_keys = results.track_keys;
        for (var track_div_id in track_keys){
            Controller.retrieve_tracks.set(track_div_id,true);
        } // end for
        Controller.get_remaining_tracks(track_keys,1000,1.5);
      }, // end onSuccess
    }); // end Ajax.Request
  }, // end rerender_track

  configure_plugin:
  function(div_id) {
    var plugin_configure_div  = $(div_id);
    var plugin_base  = document.pluginform.plugin.value;
    new Ajax.Updater(plugin_configure_div,'#',{
      parameters: {
        update: div_id,
        plugin_base: plugin_base,
      }
    });
  },

  reconfigure_plugin:
  function(plugin_action,plugin_track_name,plugin_track_div_id,pc_div_id) {
    var plugin_configure_div  = $(pc_div_id);
    var form_element = $("configure_plugin");
    new Ajax.Request('#',{
      method:     'post',
      parameters: form_element.serialize() +"&"+ $H({
            plugin_action: plugin_action,
            reconfigure_plugin: 1
          }).toQueryString(),
      onSuccess: function(transport) {
        Controller.wipe_div(pc_div_id); 
        // update plugin track if it exists
        if ( null != $(plugin_track_div_id)){
          Controller.rerender_track(plugin_track_name,plugin_track_div_id);
        }
      } // end onSuccess
    });
  },

  plugin_go:
  function(plugin_base,plugin_type,plugin_action,source) {
    if (plugin_type == 'annotator'){
      var select_box = document.pluginform.plugin;
      var track_name = select_box.options[select_box.selectedIndex].attributes.getNamedItem('track_name').value;

      this.add_track(track_name);
      // NEEDS TO CHECK THE TRACK CHECKBOX
    }
    else if (plugin_type == 'dumper'){
      var loc_str = "?plugin="+plugin_base+";plugin_action="+encodeURI(plugin_action);
      if(source == 'config'){
        var form_element = $("configure_plugin");
        window.location=loc_str + ";" + form_element.serialize();
      }
      else{
        window.location=loc_str;
      }
    }
    else if (plugin_type == 'filter'){
        alert("Not Implemented Yet");
    }
    else if (plugin_type == 'finder'){
        alert("Not Implemented Yet");
    }
  }, // end plugin_go

  wipe_div:
  function(div_id) {
    $(div_id).innerHTML = '';
  }
});

var Controller = new GBrowseController; // singleton

function initialize_page() {
  //event handlers
  ['page_title','span'].each(function(el) {

    if ($(el) != null) {
      Controller.segment_observers.set(el,1);
      $(el).observe('model:segmentChanged',function(event) {
        new Ajax.Updater(this,'#',{
  	  parameters: {update: this.id}
        });
      }
     )
    }
  });
  
  Controller.first_render();
  Overview.prototype.initialize();
  Region.prototype.initialize();
  Details.prototype.initialize();
}

