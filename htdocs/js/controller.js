/*
 controller.js -- The GBrowse controller object

 Lincoln Stein <lincoln.stein@gmail.com>
 $Id: controller.js,v 1.53 2008-09-24 23:34:43 lstein Exp $

Indentation courtesy of Emacs javascript-mode 
(http://mihai.bazon.net/projects/emacs-javascript-mode/javascript.el)

Method structure
 - Class Utility Methods
 - DOM Utility Methods
 - Update Section Methods
 - Kick-off Render Methods
 - Retrieve Rendered Track Methods
 - Track Configure Methods
 - Plugin Methods
 - Upload File Methods

*/

//  Element Names
var track_listing_id        = 'tracks_panel'; 
var external_listing_id     = 'upload_tracks_panel'; 
var overview_container_id   = 'overview_panels'; 
var region_container_id     = 'region_panels'; 
var detail_container_id     = 'detail_panels'; 
var external_utility_div_id = 'external_utility_div'; 
var edit_upload_form_id     = 'edit_upload_form';
var page_title_id           = 'page_title';
var visible_span_id         = 'span';

var GBrowseController = Class.create({

  // Class Utility Methods ******************************************
  
  initialize:
  function () {
    this.gbtracks                 = new Hash();
    this.segment_observers        = new Hash();
    this.retrieve_tracks          = new Hash();
    this.track_time_key           = new Hash();
    // segment_info holds the information used in rubber.js
    this.segment_info;
  },

  reset_after_track_load:
  // This may be a little overkill to run these after every track update but
  // since there is no "We're completely done with all the track updates for the
  // moment" hook, I don't know of another way to make sure the tracks become
  // draggable again
  function () {
    if ( null != $(overview_container_id) ){
      create_drag(overview_container_id,'track');
    }
    if ( null != $(region_container_id) ){
      create_drag(region_container_id,'track');
    }
    if ( null != $(detail_container_id) ){
      create_drag(detail_container_id,'track');
    }
  },
  
  register_track:
  function (track_name,track_type) {
    
    var gbtrack = new GBrowseTrack(track_name,track_type); 
    this.gbtracks.set(track_name,gbtrack);
    if (track_type=="scale_bar"){
      return gbtrack;
    }
    this.retrieve_tracks.set(track_name,true);
    return gbtrack;
  }, // end register_track

  // DOM Utility Methods ********************************************

  wipe_div:
  function(div_id) {
    $(div_id).innerHTML = '';
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

  append_child_from_html:
  function (child_html,parent_obj) {
    //Append new html to the appropriate section This is a bit cludgy but we
    //create a temp element, read the html into it and then move the div
    //element back out.  This keeps the other tracks intact.
    var tmp_element       = document.createElement("tmp_element");
    tmp_element.innerHTML = child_html;
    parent_obj.appendChild(tmp_element);

    // Move each child node but skip if it is a comment (class is undef)
    if (tmp_element.hasChildNodes()) {
      var children = tmp_element.childNodes;
      for (var i = 0; i < children.length; i++) {
        if (children[i].className == undefined){
          continue;
        }
        parent_obj.appendChild(children[i]);
      };
    };
    parent_obj.removeChild(tmp_element);
  },

  // Update Section Methods *****************************************
  update_sections:
  function(section_names, param_str) {

    if (param_str==null){
        param_str = '';
    }

    var request_str = "update_sections=1" + param_str;
    for (var i = 0; i < section_names.length; i++) {
      request_str += "&section_names="+section_names[i];
    }
    new Ajax.Request('#',{
      method:     'post',
      parameters: request_str,
      onSuccess: function(transport) {
        var results    = transport.responseJSON;
        var section_html = results.section_html;
        for (var section_name in section_html){
          html    = section_html[section_name];
          $(section_name).innerHTML = html;
        }
      }
    });
  },

  // Signal Change to Server Methods ********************************
  set_track_visibility:
  function(track_name,visible) {

    if ( null == $(this.gbtracks.get(track_name).track_div_id)){
      // No track div
      return;
    }

    new Ajax.Request('#',{
      method:     'post',
      parameters: {
        set_track_visibility:  1,
        visible:               visible,
        track_name:            track_name,
      },
    });
  },

  // Kick-off Render Methods ****************************************

  first_render:
  function()  {
    new Ajax.Request('#',{
      method:     'post',
      parameters: {first_render: 1},
      onSuccess: function(transport) {
        var results    = transport.responseJSON;
        var track_keys = results.track_keys;
        Controller.segment_info = results.segment_info;

        Controller.get_multiple_tracks(track_keys);
      }
    });
  },

  update_coordinates:
  function (action) {

    // submit search form if the detail panel doesn't exist
    if ( null == $(detail_container_id) ){
        document.searchform.force_submit.value = 1; 
        document.searchform.submit(); 
    }

    //Grey out image
    this.gbtracks.values().each(
      function(gbtrack) {
	    $(gbtrack.track_image_id).setOpacity(0.3);
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
    
        if (overview_scale_bar_hash){
          Controller.update_scale_bar(overview_scale_bar_hash);
        }
        if (region_scale_bar_hash){
          Controller.update_scale_bar(region_scale_bar_hash);
        }
        if (detail_scale_bar_hash){
          Controller.update_scale_bar(detail_scale_bar_hash);
        }
    
        // Update the segment sections
        Controller.update_sections( Controller.segment_observers.keys());

        Controller.get_multiple_tracks(track_keys);
      } // end onSuccess
      
    }); // end Ajax.Request
  }, // end update_coordinates

  add_track:
  function(track_name, onSuccessFunc) {

    if ( track_name == '' 
      || (this.gbtracks.get(track_name) !=null 
          && 
          null != $(this.gbtracks.get(track_name).track_div_id))
    ){
      return;
    }

    new Ajax.Request('#',{
      method:     'post',
      parameters: {
        add_track:  1,
        track_name: track_name,
      },
      onSuccess: function(transport) {
        if (onSuccessFunc!=null){
            onSuccessFunc();
        }
        var results    = transport.responseJSON;
        var track_data = results.track_data;
        for (var ret_track_name in track_data){
          var this_track_data = track_data[ret_track_name];
          var ret_gbtrack = Controller.register_track(ret_track_name,'standard') ;

          var html           = this_track_data.track_html;
          var panel_id       = this_track_data.panel_id;

          Controller.append_child_from_html(html,$(panel_id));

          if (html.substring(0,18) == "<!-- AVAILABLE -->"){
            Controller.reset_after_track_load();
          }
          else{
            var track_keys = new Array();
            time_key = create_time_key();
            track_keys[ret_track_name]=this_track_data.track_key;
            Controller.retrieve_tracks.set(ret_track_name,true);
            Controller.track_time_key.set(ret_track_name,time_key);
            Controller.get_remaining_tracks(track_keys,1000,1.1,time_key);
          }
        }
      },
    });
  },

  rerender_track:
  function(track_name) {

    var gbtrack = this.gbtracks.get(track_name);
    $(gbtrack.track_image_id).setOpacity(0.3);

    new Ajax.Request('#',{
      method:     'post',
      parameters: {
        rerender_track:  1,
        track_name: track_name,
      },
      onSuccess: function(transport) {
        var results    = transport.responseJSON;
        var track_keys = results.track_keys;
        time_key = create_time_key();
        for (var track_name in track_keys){
            Controller.retrieve_tracks.set(track_name,true);
            Controller.track_time_key.set(track_name,time_key);
        } // end for
        Controller.get_remaining_tracks(track_keys,1000,1.1,time_key);
      }, // end onSuccess
    }); // end Ajax.Request
  }, // end rerender_track

  // Retrieve Rendered Track Methods ********************************
  
  get_multiple_tracks:
  function (track_keys) {
    
    time_key = create_time_key();
    this.retrieve_tracks.keys().each(
      function(track_name) {
        Controller.retrieve_tracks.set(track_name,true);
        Controller.track_time_key.set(track_name,time_key);
      }
    );

    this.get_remaining_tracks(track_keys,1000,1.1,time_key);
  },

  // Time key is there to make sure separate calls don't trounce each other
  // Only Update if the tracks time_key matches the method's
  get_remaining_tracks:
  function (track_keys,time_out,decay,time_key){

    var track_names = [];
    var finished = true;
    var track_key_str = '';
    this.retrieve_tracks.keys().each(
      function(track_name) {
        if(Controller.retrieve_tracks.get(track_name)){
          if (Controller.track_time_key.get(track_name) == time_key){
            track_names.push(track_name);
            track_key_str += '&tk_'+escape(track_name)+"="+track_keys[track_name];
            finished = false;
          }
        }
      }
    );

    if (finished){
      return;
    }

    new Ajax.Request('#',{
      method:     'post',
      parameters: $H({ retrieve_multiple: 1, 
                       track_names:     track_names, 
		    }).toQueryString()  + track_key_str,
      onSuccess: function(transport) {
        var continue_requesting = false;
        var results    = transport.responseJSON;
        var track_html_hash = results.track_html;
        for (var track_name in track_html_hash){
          track_html    = track_html_hash[track_name];

          var gbtrack = Controller.gbtracks.get(track_name);
          if (Controller.track_time_key.get(track_name) == time_key){
            track_div = document.getElementById(gbtrack.track_div_id);
            if (track_html.substring(0,18) == "<!-- AVAILABLE -->"){
              track_div.innerHTML = track_html;
              Controller.retrieve_tracks.set(track_name,false);
            }
            else if (track_html.substring(0,16) == "<!-- EXPIRED -->"){
               $(gbtrack.track_image_id).setOpacity(0);
            }
            else if (track_html.substring(0,14) == "<!-- ERROR -->"){
               Controller.retrieve_tracks.set(track_name,false);
	       track_div.innerHTML = track_html;
            }
            else if (track_html.substring(0,16) == "<!-- DEFUNCT -->"){
               Controller.retrieve_tracks.set(track_name,false);
               $(gbtrack.track_image_id).setOpacity(0);
            }
            else {
              continue_requesting = true;
            }
          }
        }
        Controller.reset_after_track_load();
        if (continue_requesting){
          setTimeout( function() {
            Controller.get_remaining_tracks(track_keys,time_out*decay,decay,time_key)
          } ,time_out);
        }
      }, // end onSuccess
    }); // end new Ajax.Request

  }, // end get_remaining_tracks

  // Track Configure Methods ****************************************

  reconfigure_track:
  function(track_name, serialized_form, show_track) {
    new Ajax.Request('#',{
      method:     'post',
      parameters: serialized_form +"&"+ $H({
            reconfigure_track: track_name
          }).toQueryString(),
      onSuccess: function(transport) {
        var track_div_id = Controller.gbtracks.get(track_name).track_div_id;
        Balloon.prototype.hideTooltip(1);
        if (show_track){
          Controller.rerender_track(track_name);
        }
        else{
          if ($(track_div_id) != null){
            actually_remove(track_div_id);
          }
          Controller.update_sections(new Array(track_listing_id));
        }
      } // end onSuccess
    });

  },


  // Plugin Methods *************************************************

  configure_plugin:
  function(div_id) {
    var plugin_base  = document.pluginform.plugin.value;
    Controller.update_sections(new Array(div_id), '&plugin_base='+plugin_base);
  },

  reconfigure_plugin:
  function(plugin_action,plugin_track_name,pc_div_id,plugin_type) {
    var gbtrack = this.gbtracks.get(plugin_track_name);
    var form_element = $("configure_plugin");
    new Ajax.Request('#',{
      method:     'post',
      parameters: form_element.serialize() +"&"+ $H({
            plugin_action: plugin_action,
            reconfigure_plugin: 1
          }).toQueryString(),
      onSuccess: function(transport) {
        Controller.wipe_div(pc_div_id); 

        if (plugin_type == 'annotator'){
          // update plugin track if it exists
          if ( null != $(gbtrack.track_div_id)){
            Controller.rerender_track(plugin_track_name);
          }
        }
        else if (plugin_type == 'filter'){
          Controller.update_coordinates("reload segment");
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
      // Go doesn't do anything for filter
      return false; 
    }
    else if (plugin_type == 'finder'){
        alert("Not Implemented Yet");
    }
  }, // end plugin_go

  // Upload File Methods *************************************************

  edit_new_file:
  function() {
    Controller.update_sections(new Array(external_utility_div_id), '&new_edit_file=1');
  },

  edit_upload:
  function(edit_file) {
    Controller.update_sections(new Array(external_utility_div_id), '&edit_file='+edit_file);
  },

  commit_file_edit:
  function(edited_file) {
    var gbtrack = this.gbtracks.get(edited_file);
    var form_element = $(edit_upload_form_id);
    new Ajax.Request('#',{
      method:     'post',
      parameters: form_element.serialize() +"&"+ $H({
            edited_file: edited_file,
            commit_file_edit: 1
          }).toQueryString(),
      onSuccess: function(transport) {
        var results    = transport.responseJSON;
        var file_created = results.file_created;
        Controller.wipe_div(external_utility_div_id); 

        if ( 1 == file_created ){
          Controller.add_track(edited_file, function(){
            Controller.update_sections(new Array(track_listing_id,external_listing_id));
          })
        }
        else{
        // update track if it exists
          if ( null != $(gbtrack.track_div_id)){
            Controller.rerender_track(edited_file);
          }
          Controller.update_sections(new Array(external_listing_id));
        }
      } // end onSuccess
    });
  },

  delete_upload_file:
  function(file_name) {
    var gbtrack = this.gbtracks.get(file_name);
    new Ajax.Request('#',{
      method:     'post',
      parameters: {
        delete_upload_file: 1,
        file: file_name
      },
      onSuccess: function(transport) {
        actually_remove(gbtrack.track_div_id);
        Controller.update_sections(new Array(track_listing_id,external_listing_id));
      } // end onSuccess
    });
  },

  // Remote Annotations Methods *************************************************

  new_remote_track:
  function(eurl) {
    if ( eurl == ''){
        return;
    }
    Controller.add_track(eurl, function(){
      Controller.update_sections(new Array(track_listing_id,external_listing_id));
    })
  },


});

var Controller = new GBrowseController; // singleton

function initialize_page() {
  //event handlers
  [page_title_id,visible_span_id].each(function(el) {
    if ($(el) != null) {
      Controller.segment_observers.set(el,1);
    }
  });
  
  Controller.first_render();
  Overview.prototype.initialize();
  Region.prototype.initialize();
  Details.prototype.initialize();
}

function create_time_key () {
    time_obj = new Date();
    return time_obj.getTime();
}

//prototype's remove function doesn't actually remove the element from
//reachability.
function actually_remove (element_name) {
  $(element_name).remove();
  $(element_name).innerHTML = '';
  $(element_name).name = 'rmd';
  $(element_name).id = 'rmd';
}

