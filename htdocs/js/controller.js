/*
 controller.js -- The GBrowse controller object

 Lincoln Stein <lincoln.stein@gmail.com>
 Ben Faga <ben.faga@gmail.com>
 $Id$

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
var overview_container_id   = 'overview_panels'; 
var region_container_id     = 'region_panels'; 
var detail_container_id     = 'detail_panels'; 
var external_utility_div_id = 'external_utility_div'; 
var page_title_id           = 'page_title';
var galaxy_form_id          = 'galaxy_form';
var visible_span_id         = 'span';
var search_form_objects_id  = 'search_form_objects';
var userdata_table_id       = 'userdata_table_div';
var userimport_table_id     = 'userimport_table_div';

//  Sorta Constants
var expired_limit  = 1;

var GBrowseController = Class.create({

  // Class Utility Methods ******************************************
  
  initialize:
  function () {
    this.gbtracks                 = new Hash(); // maps track ids to gbtrack objects
    this.segment_observers        = new Hash();
    this.retrieve_tracks          = new Hash();
    this.ret_track_time_key       = new Hash();
    this.gbtrackname_to_id        = new Hash(); // maps unique track ids to names
    // segment_info holds the information used in rubber.js
    this.segment_info;
    this.last_update_key;
    this.tabs;

    //global config variables
    this.globals = new Hash();

  },

  set_globals:
  function(obj) {
    for(var name in obj) {
      this.globals.set(name, obj[name])
    }

    //generate *_url accessors
    var mk_url_accessor = function( conf_name, acc_name) {
      Controller[acc_name] = function(relpath) { this.globals.get(conf_name) + '/' + relpath }
    };
    mk_url_accessor( 'buttons',      'button_url'     );
    mk_url_accessor( 'balloons',     'balloon_url'    );
    mk_url_accessor( 'openid',       'openid_url'     );
    mk_url_accessor( 'js',           'js_url'         );
    mk_url_accessor( 'gbrowse_help', 'help_url'       );
    mk_url_accessor( 'stylesheet',   'stylesheet_url' );
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
  function (track_id,track_name,track_type,track_section) {

    if (this.gbtracks.get(track_id) != null)
      return;

    var gbtrack = new GBrowseTrack(track_id,track_name,track_type,track_section); 

    this.gbtracks.set(track_id,gbtrack);

    if (this.gbtrackname_to_id.get(track_name) == null)
       this.gbtrackname_to_id.set(track_name,new Hash());
    this.gbtrackname_to_id.get(track_name).set(track_id,1);

    if (track_type=="scale_bar"){
      return gbtrack;
    }
    this.retrieve_tracks.set(track_id,true);
    return gbtrack;
  }, // end register_track

  unregister_track:
  function (track_name) {
    var id_hash  = this.gbtrackname_to_id.get(track_name);
    if (id_hash != null) {
       var ids = id_hash.keys();
       for (var i=0;i<ids.length;i++) this.gbtracks.unset(ids[i]);
       this.gbtrackname_to_id.unset(track_name);
    }
  }, // end unregister_track

  unregister_gbtrack:
  function (gbtrack) {
      var id_hash = this.gbtrackname_to_id.get(gbtrack.track_name);
      if (id_hash != null)
           id_hash.unset(gbtrack.track_id);
      if (this.gbtracks.get(gbtrack.track_id) != null)
          this.gbtracks.unset(gbtrack.track_id);
  },

  // Pass an iterator to execute something on each track
  // Call as this.each_track(function(track){}) to iterate over all gbtracks.
  // Call as this.each_track('track_name',function(track){}) to iterate over
  // all tracks named 'track_name'
  each_track:
  function () {
     if (arguments.length >= 2) {
       var track_name = arguments[0];
       var iterator   = arguments[1];

       if (this.gbtracks.get(track_name) != null) {
          iterator(this.gbtracks.get(track_name));
       } else if (this.gbtrackname_to_id.get(track_name) != null) {
         var ids        = this.gbtrackname_to_id.get(track_name).keys();
         for (var i=0;i<ids.length;i++)
             iterator(this.gbtracks.get(ids[i])); // I don't know why each() doesn't work here
       }

     } else {
       var iterator   = arguments[0];
       this.gbtracks.keys().each(
          function(key) {
	     var track=this.gbtracks.get(key);
             iterator(track);
          },this);
     }
  }, //end each_track

  track_exists:
  function (track_name) {
     return this.gbtrackname_to_id.get(track_name) != null;
  },


  // Sets the time key for the tracks so we know if one is outdated
  set_last_update_keys:
  function (track_keys) {
    var last_update_key  = create_time_key();
    this.last_update_key = last_update_key;

    var track_key_hash = new Hash;
    for (var track_name in track_keys)
    	track_key_hash.set(track_name,1);

    this.each_track(function(gbtrack) {
        if (track_key_hash.get(gbtrack.track_name) != null) {
	   gbtrack.set_last_update_key(last_update_key);
	}
    });
  }, // end set_last_update_keys

  // Sets the time key for a single track
  set_last_update_key:
  function (gbtrack) {
    var last_update_key = create_time_key();
    gbtrack.set_last_update_key(this.last_update_key);
    
  },

  // Hides the detail tracks in case they shouldn't be displayed for some reason
  hide_detail_tracks:
  function () {
    this.each_track(function(gbtrack) {
        if (gbtrack.is_standard_track() 
            && gbtrack.track_section == 'detail'){
          $(gbtrack.track_image_id).setOpacity(0.2);
        }    	
    });
  }, 
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
        cursor:     'text'
    });
    image.setOpacity(1);
    image.ancestors()[0].setStyle({width: bar_obj.width+'px'});
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
  function(section_names, param_str, scroll_there, spin, onSuccessFunc) {

    if (param_str==null){
        param_str = '';
    }
    if (scroll_there==null) {
        scroll_there=false;
    }
    if (spin == null) {
        spin = false;
    }

    var request_str = "action=update_sections" + param_str;
    for (var i = 0; i < section_names.length; i++) {
      if (spin)
        $(section_names[i]).innerHTML = '<img src="' + this.button_url('spinner.gif') + '" alt="Working..." />';
      request_str += "&section_names="+section_names[i];
    }

    new Ajax.Request(document.URL,{
      method:     'post',
      parameters: request_str,
      onSuccess: function(transport) {
        var results      = transport.responseJSON;
        var section_html = results.section_html;
        for (var section_name in section_html){
          html    = section_html[section_name];
          $(section_name).innerHTML = html;
	  if (scroll_there)
	    new Effect.ScrollTo(section_name);
	    if ((section_name=="search_form_objects") 
	      && ($('autocomplete_choices') != null)) {
	    	initAutocomplete();
	    }
	  if (section_name == page_title_id)
	     document.title = $(section_name).innerHTML;
	  if (onSuccessFunc != null) onSuccessFunc();
        }
      }
    });
  },

  // General option setting used for grid, cache and tooltips ******
   set_display_option:
   function(option,value) {

     var param = {action: 'set_display_option'};
     param[option] = value;
     new Ajax.Request(document.URL,
            {
		    method: 'post', 
		    parameters: param,
		    onComplete:  function (transport) {
		      Controller.update_coordinates('left 0'); // causes an elegant panel refresh
		    } 
            }
     );

   },

  // Signal Change to Server Methods ********************************
  set_track_visibility:
  function(track_id,visible) {

    var gbtrack  = this.gbtracks.get(track_id);
    if (gbtrack == null) return;

    var track_name = gbtrack.track_name;

    this.each_track(track_id,function(gbtrack) {

      new Ajax.Request(document.URL,{
        method:     'post',
        parameters: {
	  action:     'set_track_visibility',
          visible:    visible,
          track_name: track_name
        },
        onSuccess: function(transport) {
          if (visible && 
	      gbtrack.get_last_update_key() == null ||
	      gbtrack.get_last_update_key() < Controller.last_update_key) {
            Controller.rerender_track(gbtrack.track_id);
          }
        }
      });
    });
  },

  // Kick-off Render Methods ****************************************

  update_coordinates:
  function (action) {

    // submit search form if the detail panel doesn't exist
    if ( null == $(detail_container_id) ){
        document.searchform.force_submit.value = 1; 
        document.searchform.submit(); 
    }

    this.busy();

    //Grey out image
    this.each_track(function(gbtrack) {
         if ($(gbtrack.track_image_id) != null)
	    $(gbtrack.track_image_id).setOpacity(0.3);
	 //  else
	 //  alert('REPORT THIS BUG: element '+gbtrack.track_image_id+' should not be null');
    });
    

    new Ajax.Request(document.URL,{
      method:     'post',
      parameters: {action:   'navigate',  // 'action'   triggers an async call
                   navigate: action       // 'navigate' is an argument passed to the async routine
                  },
      onSuccess: function(transport) {
	var results                 = transport.responseJSON;
        Controller.segment_info     = results.segment_info;
	var track_keys              = results.track_keys;
	var overview_scale_bar_hash = results.overview_scale_bar;
	var region_scale_bar_hash   = results.region_scale_bar;
	var detail_scale_bar_hash   = results.detail_scale_bar;
        Controller.set_last_update_keys(track_keys);

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
        $('details_msg').innerHTML = results.details_msg;
        Controller.get_multiple_tracks(track_keys);
        if (results.display_details == 0){
          Controller.hide_detail_tracks();
        }
	Controller.idle();
      } // end onSuccess
      
    }); // end Ajax.Request

  }, // end update_coordinates

  scroll:
  function (direction,length_units) {
     var length = this.segment_info.detail_stop - this.segment_info.detail_start + 1;
     this.update_coordinates(direction + ' ' + Math.round(length_units*length));
  }, // end scroll

  add_track:
  function(track_name, onSuccessFunc, force) {
    var track_names = new Array(track_name);
    this.add_tracks(track_names,onSuccessFunc,force);
  },

  add_tracks:
  function(track_names, onSuccessFunc, force) {

    if (force == null) force=false;

    var request_str = "action=add_tracks";
    var found_track = false;
    for (var i = 0; i < track_names.length; i++) {
      var track_name = track_names[i];
      if ( force || !this.track_exists(track_name) ) {
        request_str += "&track_names="+encodeURIComponent(track_name);
        found_track = true;
      }
    }

    if (!found_track) return false;

    new Ajax.Request(document.URL,{
      method:     'post',
      parameters: request_str,
      onSuccess: function(transport) {
        if (onSuccessFunc!=null){
            onSuccessFunc();
        }
        var results    = transport.responseJSON;
        var track_data = results.track_data;
        var track_keys = new Object();
        var get_tracks = false;

        for (var ret_track_id in track_data){

	  if (Controller.gbtracks.get(ret_track_id) != null) {
	     continue; //oops already know this one
	  }

          var this_track_data = track_data[ret_track_id];
          var ret_gbtrack     = Controller.register_track(
	    ret_track_id,
            this_track_data.track_name,
            'standard',
            this_track_data.track_section
          );

          Controller.set_last_update_key(ret_gbtrack)
          var html           = this_track_data.track_html;
          var panel_id       = this_track_data.panel_id;

          Controller.append_child_from_html(html,$(panel_id));

          if (this_track_data.display_details == 0){
            $(ret_gbtrack.track_image_id).setOpacity(0);
          }
          else{
            track_keys[ret_track_id]=this_track_data.track_key;
            get_tracks = true;
          }
        } // end for (var ret_track_name...
        if( get_tracks){
          Controller.get_multiple_tracks(track_keys);
        }
      }
    });
    return true;
  },

  busy:
  function() {
    var bi = $('busy_indicator');
    var top  = document.body.scrollTop||document.documentElement.scrollTop;
    bi.style.top=top+"px";
    bi.style.left=5+"px";
    bi.show();
  },

  idle:
  function() {
    var bi = $('busy_indicator');
    bi.hide();
  },

  rerender_track:
  function(track_id,scroll_there,nocache) {

    if (scroll_there == null)
      scroll_there = false;
    if (nocache == null)
      nocache = false;

    this.busy();

    this.each_track(track_id,function(gbtrack) {

       $(gbtrack.track_image_id).setOpacity(0.3);
       Controller.set_last_update_key(gbtrack);

       new Ajax.Request(document.URL,{
         method:     'post',
         parameters: {
           action:          'rerender_track',
           track_id:        gbtrack.track_id,
	   nocache:         nocache ? 1 : 0
         },
         onSuccess: function(transport) {
           var results    = transport.responseJSON;
           var track_keys = results.track_keys;
           if (results.display_details == 0){
             $(gbtrack.track_image_id).setOpacity(0);
           }
           else{
             time_key = create_time_key();
             for (var track_id in track_keys){
                 Controller.retrieve_tracks.set(gbtrack.track_id,true);
                 Controller.ret_track_time_key.set(gbtrack.track_id,time_key);
             } // end for
             Controller.get_remaining_tracks(track_keys,1000,1.1,time_key);
           } 
   	   if (scroll_there) {
	      new Effect.ScrollTo(gbtrack.track_div_id);
	   }
         } // end onSuccess
       }); // end Ajax.Request
    }); //end each_track()

  }, // end rerender_track

  scroll_to_matching_track:
  function scroll_to_matching_track(partial_name) {
     var tracks = $$('span.titlebar');
     var first_track = tracks.find(function(n) {
                         var result = n.id.include(partial_name)
                                      && n.visible();
                         return result;
                           }
			);
     if (first_track != null) {
         new Effect.ScrollTo(first_track.id);
     }
  },

  delete_track:
  function(track_name) {
      this.each_track(track_name,function(gb) {
	  Controller.unregister_track(gb.track_name);
	  actually_remove(gb.track_div_id);         
      });
  }, // end delete_track

  // Retrieve Rendered Track Methods ********************************
  
  get_multiple_tracks:
  function (track_keys) {

    time_key = create_time_key();
    $H(track_keys).keys().each( 
      function(track_id) {
        Controller.retrieve_tracks.set(track_id,true);
        Controller.ret_track_time_key.set(track_id,time_key);
      }
    );

    this.get_remaining_tracks(track_keys,1000,1.1,time_key);
  },

  // Time key is there to make sure separate calls don't trounce each other
  // Only Update if the tracks time_key matches the method's
  get_remaining_tracks:
  function (track_keys,time_out,decay,time_key){

    var track_ids = [];
    var finished = true;
    var track_key_str = '';
    this.retrieve_tracks.keys().each(
      function(track_id) {
        if(Controller.retrieve_tracks.get(track_id)){
          if (Controller.ret_track_time_key.get(track_id) == time_key){
            track_ids.push(track_id);
            track_key_str += '&tk_'+escape(track_id)+"="+track_keys[track_id];
            finished = false;
          }
        }
      }
    );

    if (finished) {
      this.idle();
      return;
    }

    new Ajax.Request(document.URL,{
      method:     'post',
      parameters: $H({ action:        'retrieve_multiple', 
                       track_ids:     track_ids
		    }).toQueryString()  + track_key_str,
      onSuccess: function(transport) {
        var continue_requesting = false;
        var results             = transport.responseJSON;
        var track_html_hash     = results.track_html;
        for (var track_id in track_html_hash){
          track_html            = track_html_hash[track_id];

          var gbtrack = Controller.gbtracks.get(track_id);
          if (Controller.ret_track_time_key.get(track_id) == time_key){
            track_div = document.getElementById(gbtrack.track_div_id);
            if (track_html.substring(0,18) == "<!-- AVAILABLE -->"){
              track_div.innerHTML = track_html;
              gbtrack.track_resolved();
              Controller.retrieve_tracks.set(track_id,false);
            }
            else if (track_html.substring(0,16) == "<!-- EXPIRED -->"){
              Controller.retrieve_tracks.set(track_id,false);
              if (gbtrack.expired_count >= expired_limit){
                $(gbtrack.track_image_id).setOpacity(0);
              }
              else{
                gbtrack.increment_expired_count();
                Controller.rerender_track(track_id);
              }
            }
            else if (track_html.substring(0,14) == "<!-- ERROR -->"){
              gbtrack.track_resolved();
              Controller.retrieve_tracks.set(track_id,false);
              track_div.innerHTML = track_html;
            }
            else if (track_html.substring(0,16) == "<!-- DEFUNCT -->"){
              gbtrack.track_resolved();
              Controller.retrieve_tracks.set(track_id,false);
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
        } else {
	    Controller.idle();
	}
      } // end onSuccess
    }); // end new Ajax.Request

  }, // end get_remaining_tracks

  // Track Configure Methods ****************************************

  reconfigure_track:
  function(track_id, form_element, semantic_label) {

    if (form_element==null)
       form_element = $("track_config_form");
    else
       Element.extend(form_element);

    var show_box   = form_element['show_track'];
    var show_track = $(show_box).getValue();

    new Ajax.Request(document.URL,{
      method:     'post',
      parameters: form_element.serialize() +"&"+ $H({
            action:         'reconfigure_track',
	    track:          track_id,
	    semantic_label: semantic_label
          }).toQueryString(),
      onSuccess: function(transport) {
        var track_div_id = Controller.gbtracks.get(track_id).track_div_id;
        Balloon.prototype.hideTooltip(1);
        if (show_track == track_id){
          Controller.rerender_track(track_id,false,false);
        }
        else{
          if ($(track_div_id) != null){
            actually_remove(track_div_id);
          }
          Controller.update_sections(new Array(track_listing_id),null,null,true);
        }
      } // end onSuccess
    });

  },

  filter_subtrack:
  function(track_id, form_element) {

    new Ajax.Request(document.URL,{
      method:     'post',
      parameters: form_element.serialize() +"&"+ $H({
            action:  'filter_subtrack',
	    track:   track_id
          }).toQueryString(),
      onSuccess: function(transport) {
        Balloon.prototype.hideTooltip(1);
        Controller.rerender_track(track_id,true);
      }, // end onSuccess
      onFailure: function(transport) {
        Balloon.prototype.hideTooltip(1);
      }
    });
  },

  // Plugin Methods *************************************************

  configure_plugin:
  function(div_id) {
    var plugin_base  = document.pluginform.plugin.value;
    this.update_sections(new Array(div_id), '&plugin_base='+plugin_base,null,null,true);
    new Effect.ScrollTo(div_id);
  },

  reconfigure_plugin:
  function(plugin_action,plugin_track_id,pc_div_id,plugin_type,form_element) {
    if (form_element==null)
       form_element = $("configure_plugin");
    else
       Element.extend(form_element);

    new Ajax.Request(document.URL,{
      method:     'post',
      parameters: form_element.serialize() +"&"+ $H({
            plugin_action: plugin_action,
	    action:  'reconfigure_plugin'
          }).toQueryString(),

      onSuccess: function(transport) {
        if (pc_div_id != null) Controller.wipe_div(pc_div_id); 

        if (plugin_type == 'annotator'){
	  Controller.each_track(plugin_track_id,function(gbtrack) {
              Controller.rerender_track(gbtrack.track_id,true);
            });
        }
        else if (plugin_type == 'filter') {
          Controller.update_coordinates("reload segment");
	  Controller.update_sections(new Array(track_listing_id),'',1,false);
	}
        else if (plugin_type == 'highlighter') {
          Controller.update_coordinates("reload segment");
        }
	else if (plugin_type == 'trackfilter') {
	  Controller.update_sections(new Array(track_listing_id),'',1,false);
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
      Controller.update_sections(new Array(track_listing_id),null,null,false);
    }
    else if (plugin_type == 'dumper'){
      var loc_str = "?plugin="+plugin_base+";plugin_action="+encodeURI(plugin_action);
      if(source == 'config'){
        var form_element = $("configure_plugin");
        window.open(loc_str + ";" + form_element.serialize());
      }
      else{
	window.open(loc_str);
      }
    }
    else if (plugin_type == 'filter'){
      // Go doesn't do anything for filter
      return false; 
    }
    else if (plugin_type == 'finder'){
        alert('Searching for ' + $F('landmark_search_field') + ' via ' + $F('plugin'));
	document.searchform.plugin_find.value  = $F('plugin');
	document.searchform.force_submit.value = 1;
	document.searchform.submit();
    }
  }, // end plugin_go

  cancel_upload:
  function(destination,upload_id) {
       new Ajax.Updater(destination,
                        document.URL,{
              method:    'post',
              parameters: {
                              action: 'cancel_upload',
			      upload_id: upload_id
                          }
        });
  },

  // Utility methods *********************************
  show_error:
  function (message,details) {
      var outerdiv    = $('errordiv');
      var innerdiv    = $('errormsg');
      var detailsdiv  = $('errordetails');
      if (innerdiv != null) {
          var caption = detailsdiv.visible() ? 'Hide details' : 'Show details';
	  innerdiv.innerHTML = message +
                               ' <a id="detailscaption" href="javascript:void(0)" onClick="Controller.show_hide_errordetails()">'
			       +caption
			       +'</a>';
      }			     
      if (detailsdiv != null) {
          detailsdiv.innerHTML  = details;
      }
      if (outerdiv != null) {
         scroll(0,0);
	 new Effect.BlindDown(outerdiv);
      }
  },

  hide_error:
  function () {
      var outerdiv   = $('errordiv');
      var detailsdiv = $('errordetails');
      if (outerdiv != null)
	  new Effect.BlindUp(outerdiv);
      return false;
  },

 show_hide_errordetails:
 function () {
    var detailsdiv = $('errordetails');
    var caption    = $('detailscaption');
    if (detailsdiv == null) return;
    if (caption    == null) return;
    if (detailsdiv.visible()) {
       caption.innerHTML="Show details";
       detailsdiv.hide();
    } else {
       caption.innerHTML="Hide details";
       detailsdiv.show();
    }
 },

  edit_upload_description:
  function(upload_name,container_element) {
      if (container_element == null)
	  return true;
      container_element.setStyle({
	      border: '2px',
	      inset:  'black',
	      backgroundColor:'beige',
	      padding:'5px 5px 5px 5px'
		  });
      var r = document.createRange();
      r.selectNodeContents(container_element);
      window.getSelection().addRange(r);
      Event.observe(container_element,'keypress',this.set_upload_description);
      Event.observe(container_element,'blur',this.set_upload_description);
  },

  set_upload_description:
  function(event) {
      var el = event.findElement();
      if (event.type=='blur' || event.keyCode==Event.KEY_RETURN) {
	  var upload_name = el.id.sub('_description$','');
	  var desc        = el.innerHTML;
	  el.innerHTML  = '<img src="' + this.button_url('spinner.gif') + ' alt="Working..." />';
	  new Ajax.Request(document.URL, {
		      method:      'post',
		      parameters:{  
		          action: 'set_upload_description',
			  upload_name: upload_name,
			  description: desc
		      },
		      onSuccess: function(transport) {
		      Controller.update_sections(new Array(userdata_table_id,userimport_table_id))
		      }
	       });
	  el.stopObserving('keypress');
	  el.stopObserving('blur');
	  el.blur();
	  return true;
      }
      if (event.keyCode==Event.KEY_ESC) {
          el.innerHTML  = '<img src="' + this.button_url('spinner.gif') + '" alt="Working..." />';
	  Controller.update_sections(new Array(userdata_table_id,userimport_table_id));
	  el.stopObserving('keypress');
	  el.stopObserving('blur');
	  el.blur();
	  return true;
      }
      return false;
  },

  // downloadUserTrackSource() is called to populate the user track edit field
  // with source or configuration data for the track
  downloadUserTrackSource:
  function (destination,fileName,sourceFile) {
      new Ajax.Updater(destination,
                       document.URL, 
		       {
		         method:     'post',
			 parameters: {
			     userdata_download: sourceFile,
                                         track: fileName
			 }
		       });

  },

  // uploadUserTrackSource() is called to submit a user track edit field
  // to the server
  uploadUserTrackSource:
  function (sourceField,fileName,sourceFile,editElement) {

     var upload_id  = 'upload_' + Math.floor(Math.random() * 99999);

     new Ajax.Request(document.URL, {
     	 method:       'post',
	 parameters:   { action:     'modifyUserData',
                         track:      fileName,
                         sourceFile: sourceFile,
			 upload_id:  upload_id,
			 data:       $F(sourceField)},
         onCreate:    function() {
	      if ($(editElement) != null) {
	      	 $(editElement).innerHTML = '<div id="'+upload_id+'_form'+'"></div>'
                               		   +'<div id="'+upload_id+'_status'+'"></div>';
	      }
	      startAjaxUpload(upload_id);
	     },
         onSuccess:   function (transport) {
	 	          if ($(editElement) != null) $(editElement).remove();
			  var r = transport.responseJSON;
			  r.tracks.each(function(t) {
			  	      Controller.rerender_track(t,true,true);
				      });
		          var updater = Ajax_Status_Updater.get(upload_id);
			  if (updater != null) updater.stop();
		          Controller.update_sections(new Array(userdata_table_id,userimport_table_id,track_listing_id));
	               }
         });
  },

// monitor_upload is redundant and needs to be refactored
// the idea is to register a new upload
  monitor_upload:
  function (upload_id,upload_name) {
  	new Ajax.Request(document.URL, {
	    method:     'post',
	    parameters: {
	    		action:      'register_upload',
			upload_id:   upload_id,
			upload_name: upload_name
	      }
	    });
	startAjaxUpload(upload_id);
  },

  select_tab:
  function (tab_id) {
     if (this.tabs != null) {
       this.tabs.select_tab(tab_id);
     }
  }


});

var Controller = new GBrowseController; // singleton

function initialize_page() {

  // These statements initialize the tabbing
  Controller.tabs = new TabbedSection(['main_page','custom_tracks_page','settings_page']);

  //event handlers
    [page_title_id,visible_span_id,galaxy_form_id,search_form_objects_id].each(function(el) {
    if ($(el) != null) {
      Controller.segment_observers.set(el,1);
    }
  });
  
  // The next statement is to avoid the scalebars from being "out of sync"
  // when manually advancing the browser with its forward/backward buttons.
  // Unfortunately it causes an infinite loop when there are multiple regions!
  if ($(detail_container_id) != null)
      Controller.update_coordinates('left 0');

  // These statements get the rubberbanding running.
  Overview.prototype.initialize();
  Region.prototype.initialize();
  Details.prototype.initialize();
  if ($('autocomplete_choices') != null) 
       initAutocomplete();

}

// set the colors for the rubberband regions
function set_dragcolors(color) {
    if (overviewObject != null)
     overviewObject.background = color;
    if (regionObject != null)
     regionObject.background   = color;
    if (detailsObject != null)
     detailsObject.background  = color;
}

function create_time_key () {
    time_obj = new Date();
    return time_obj.getTime();
}

//prototype's remove function doesn't actually remove the element from
//reachability.
function actually_remove (element_name) {
  var element = $(element_name);
  if (element==null) return;
  var parent = element.parentNode;
  parent.removeChild(element);
}

