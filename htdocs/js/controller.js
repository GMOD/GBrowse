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
var custom_tracks_id        = 'custom_tracks';
var community_tracks_id     = 'community_tracks';
var GlobalDrag;

//  Sorta Constants
var expired_limit  = 1;



var GBrowseController = Class.create({

  // Class Utility Methods ******************************************

	set_url:
	function(url) {
		this.url = url;
	},

	initialize:
	function () {
	        var url  = document.URL;
		var q    = url.indexOf('?');
                if (q >= 0) url  = url.substr(0,q);
		this.url = url;
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
		for (var name in obj) {
			this.globals.set(name, obj[name])
		}

		var me = this;

		//generate *_url accessors
		var mk_url_accessor = function( conf_name, acc_name) {
			me[acc_name] = function(relpath) { return this.globals.get(conf_name) + '/' + relpath; }
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
		TrackPan.update_draggables();
		updateRuler();
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
                var ids = this.gbtrackname_to_id.get(track_name).keys();
                for (var i=0;i<ids.length;i++)
                iterator(this.gbtracks.get(ids[i])); // I don't know why each() doesn't work here
            }
        } else {
            var iterator   = arguments[0];
            this.gbtracks.keys().each(
                function(key) {
                    var track=this.gbtracks.get(key);
                    iterator(track);
                }, this
            );
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
            if (gbtrack.is_standard_track() && gbtrack.track_section == 'detail'){
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
    function (child_html,parent_obj,onTop) {
        //Append new html to the appropriate section This is a bit cludgy but we
        //create a temp element, read the html into it and then move the div
        //element back out.  This keeps the other tracks intact.
        if (onTop == null) onTop = false;

        var tmp_element       = document.createElement("tmp_element");
        tmp_element.innerHTML = child_html;

        var tracks      = parent_obj.getElementsByClassName('track');
        var first_track = tracks[0];

        if (onTop && first_track != null)
            parent_obj.insertBefore(tmp_element,first_track[0]);
        else
            parent_obj.appendChild(tmp_element);
        
        // Move each child node but skip if it is a comment (class is undef)
        if (tmp_element.hasChildNodes()) {
            var children = tmp_element.childNodes;
            for (var i = 0; i < children.length; i++) {
                if (children[i].className == undefined)
                    continue;
                if (onTop && first_track != null)
                    parent_obj.insertBefore(children[i],first_track);
                else
                    parent_obj.appendChild(children[i]);
            }
        }
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
                $(section_names[i]).update(new Element("img", 
						       {src: Controller.button_url('spinner.gif'), 
							alt: Controller.translate('WORKING')}) );
            request_str += "&section_names="+section_names[i];
        }

        new Ajax.Request(Controller.url, {
            method:     'post',
            parameters: request_str,
            onSuccess: function(transport) {
                var results      = transport.responseJSON;
                var section_html = results.section_html;
                for (var section_name in section_html) {
                    $(section_name).setOpacity(1.0);
                    html = section_html[section_name];
                    $(section_name).innerHTML = html;
                    if (scroll_there)
                        new Effect.ScrollTo(section_name);
                    if (    (section_name==search_form_objects_id) && ($('autocomplete_choices') != null)
			  ||(section_name==community_tracks_id)    && ($('autocomplete_upload_filter') != null))
                        initAutocomplete();
                    if (section_name == page_title_id)
                        document.title = $(section_name).innerHTML;
                    if (onSuccessFunc != null)
                        onSuccessFunc();
                }
                checkSummaries();
            }
        });
    },

    // General option setting used for grid, cache and tooltips ******
    set_display_option:
    function(option, value) {
        var param = {action: 'set_display_option'};
        param[option] = value;
        new Ajax.Request(Controller.url,
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

            new Ajax.Request(Controller.url,{
                method:     'post',
                parameters: {
                    action:     'set_track_visibility',
                    visible:    visible,
                    track_name: track_name
                },
                onSuccess: function(transport) {
                    if (visible && gbtrack.get_last_update_key() == null || gbtrack.get_last_update_key() < Controller.last_update_key) {
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

        TrackPan.grey_out_markers();
        $('ruler_handle').setOpacity(0.3);
        $('detail_scale_scale').setOpacity(0.3);

        //Grey out image
        this.each_track(function(gbtrack) {
            if ($(gbtrack.track_image_id) != null)
                $(gbtrack.track_image_id).setOpacity(0.3);
            //  else
            //  alert('REPORT THIS BUG: element '+gbtrack.track_image_id+' should not be null');
        });


        new Ajax.Request(Controller.url, {
            method:     'post',
            parameters: {
                action:     'navigate',  // 'action'   triggers an async call
                navigate:   action,      // 'navigate' is an argument passed to the async routine
                view_start: Math.round(TrackPan.get_start()),
                view_stop:  Math.round(TrackPan.get_stop())
            },
            onSuccess: function(transport) {
                var results                 = transport.responseJSON;
                Controller.segment_info     = results.segment_info;
                var track_keys              = results.track_keys;
                var overview_scale_bar_hash = results.overview_scale_bar;
                var region_scale_bar_hash   = results.region_scale_bar;
                var detail_scale_bar_hash   = results.detail_scale_bar;
                Controller.set_last_update_keys(track_keys);

                if (overview_scale_bar_hash) {
                    Controller.update_scale_bar(overview_scale_bar_hash);
                    $('overview_panels').setStyle({width: overview_scale_bar_hash.width+'px'});
                }
                if (region_scale_bar_hash) {
                    Controller.update_scale_bar(region_scale_bar_hash);
                    $('region_panels').setStyle({width: region_scale_bar_hash.width+'px'});
                }
                if (detail_scale_bar_hash) {
                    Controller.update_scale_bar(detail_scale_bar_hash);
                    $('detail_panels').setStyle({width: detail_scale_bar_hash.view_width+'px'});

                    var detail_width         = Controller.segment_info.detail_width;
                    var details_pixel_ratio  = Controller.segment_info.details_pixel_ratio;
                    var scale_width          = Math.round(detail_scale_bar_hash.scale_size / details_pixel_ratio) - 1;
                    var scale_left           = Math.round((Controller.segment_info.overview_width - scale_width) / 2) - 30;

                    var scale_div = $("detail_scale_scale");
                    if (scale_div) {
                        scale_div.innerHTML = detail_scale_bar_hash.scale_label + 
                            "<span style='display: inline-block; margin-left:5px; margin-bottom:4px; border-left: 1px solid black; border-right: 1px solid black; height:8px'>" +
                            "<span style='display: inline-block; border-bottom: 1px solid black; height: 4px; width:" + scale_width + "px'</span></span>";
                        $('ruler_handle').setOpacity(1);
                        scale_div.setOpacity(1);
                        scale_div.setStyle({ left: scale_left+'px' });
                    }
                }
                // Update the segment sections
                Controller.update_sections( Controller.segment_observers.keys());
                $('details_msg').innerHTML = results.details_msg;
                Controller.get_multiple_tracks(track_keys);
                TrackPan.make_details_draggable();
                if (results.display_details == 0)
                    Controller.hide_detail_tracks();
            } // end onSuccess
        }); // end Ajax.Request
    }, // end update_coordinates

    scroll:
    function (direction,length_units) {
        if (!TrackPan.scroll(direction,length_units)) {
            var view_length = (parseInt(Controller.segment_info.detail_stop) - parseInt(Controller.segment_info.detail_start)) / parseFloat(Controller.segment_info.details_mult);
            this.update_coordinates(direction + ' ' + Math.round(length_units*view_length));
        }
    }, // end scroll

    add_track:
    function(track_name, onSuccessFunc, force) {
        var track_names = new Array(track_name);
        this.add_tracks(track_names,onSuccessFunc,force);
    },

    add_tracks:
    function(track_names, onSuccessFunc, force, onTop) {

        if (force == null)
            force = false;

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

        this.busy();
        new Ajax.Request(Controller.url, {
            method:     'post',
            parameters: request_str,
            onSuccess: function(transport) {
                if (onSuccessFunc!=null)
                    onSuccessFunc();
                var results    = transport.responseJSON;
                var track_data = results.track_data;
                var track_keys = new Object();
                var get_tracks = false;

                for (var ret_track_id in track_data) {

                    if (Controller.gbtracks.get(ret_track_id) != null)
                        continue; //oops already know this one

                    var this_track_data = track_data[ret_track_id];
                    var ret_gbtrack     = Controller.register_track (
                        ret_track_id,
                        this_track_data.track_name,
                        'standard',
                        this_track_data.track_section
                    );

                    Controller.set_last_update_key(ret_gbtrack)
                    var html           = this_track_data.track_html;
                    var panel_id       = this_track_data.panel_id;

                    //Controller.append_child_from_html(html,$(panel_id),onTop);
		    // force true - experimental
		    Controller.append_child_from_html(html,$(panel_id),true);

                    if (this_track_data.display_details == 0) {
                        $(ret_gbtrack.track_image_id).setOpacity(0);
                    } else {
                        track_keys[ret_track_id]=this_track_data.track_key;
                        get_tracks = true;
                    }
                } // end for (var ret_track_name...
                if( get_tracks)
                    Controller.get_multiple_tracks(track_keys);
                else
                    Controller.idle();
            }
        });
        return true;
    },

    busy:
    function() {
        var bi = $('busy_indicator');
        var top  = document.body.scrollTop||document.documentElement.scrollTop;
        bi.style.top  =5+"px";
        bi.style.left =5+"px";
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

            new Ajax.Request(Controller.url,{
                method:     'post',
                parameters: {
                    action:          'rerender_track',
                    track_id:        gbtrack.track_id,
                    nocache:         nocache ? 1 : 0
                },
                onSuccess: function(transport) {
                    var results    = transport.responseJSON;
                    var track_keys = results.track_keys;
                    if (results.display_details == 0) {
                        $(gbtrack.track_image_id).setOpacity(0);
                    } else {
                        time_key = create_time_key();
                        for (var track_id in track_keys) {
                            Controller.retrieve_tracks.set(gbtrack.track_id,true);
                            Controller.ret_track_time_key.set(gbtrack.track_id,time_key);
                        } // end for
                        Controller.get_remaining_tracks(track_keys,1000,1.1,time_key);
                    } 
                    if (scroll_there)
                        new Effect.ScrollTo(gbtrack.track_div_id,{queue: 'end'});
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
        });
        if (first_track != null) {
	    new Effect.ScrollTo(first_track,
				{  queue:'end' }
				);
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
        this.busy();
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

        new Ajax.Request(Controller.url, {
            method:     'post',
            parameters: $H({
                action:        'retrieve_multiple', 
                track_ids:     track_ids
            }).toQueryString() + track_key_str,
            onSuccess: function(transport) {
                var continue_requesting = false;
                var results             = transport.responseJSON;
                var track_html_hash     = results.track_html;
                for (var track_id in track_html_hash) {
                    track_html            = track_html_hash[track_id];

                    var gbtrack = Controller.gbtracks.get(track_id);
                    if (Controller.ret_track_time_key.get(track_id) == time_key){
                        track_div = document.getElementById(gbtrack.track_div_id);
                        if (track_html.substring(0,18) == "<!-- AVAILABLE -->"){
                            track_div.innerHTML = track_html;
                            gbtrack.track_resolved();
                            Controller.retrieve_tracks.set(track_id,false);
                        } else if (track_html.substring(0,16) == "<!-- EXPIRED -->") {
                            Controller.retrieve_tracks.set(track_id,false);
                            if (gbtrack.expired_count >= expired_limit){
                                $(gbtrack.track_image_id).setOpacity(0);
                            } else {
                                gbtrack.increment_expired_count();
                                Controller.rerender_track(track_id);
                            }
                        } else if (track_html.substring(0,14) == "<!-- ERROR -->") {
                            gbtrack.track_resolved();
                            Controller.retrieve_tracks.set(track_id,false);
                            track_div.innerHTML = track_html;
                        } else if (track_html.substring(0,16) == "<!-- DEFUNCT -->") {
                        gbtrack.track_resolved();
                        Controller.retrieve_tracks.set(track_id,false);
                        $(gbtrack.track_image_id).setOpacity(0);
                        } else {
                            continue_requesting = true;
                        }
                    }
                }
                Controller.reset_after_track_load();
                if (continue_requesting) {
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
    function(track_id, form_element, mode) {

        if (form_element==null)
            form_element = $("track_config_form");
        else
            Element.extend(form_element);

        if (mode==null)
            mode='normal';

        var show_box   = form_element['show_track'];
        var show_track = $(show_box).getValue();

        new Ajax.Request(Controller.url, {
                method:     'post',
                parameters: form_element.serialize() +"&"+ $H({
                action:         'reconfigure_track',
                track:          track_id,
                mode:           mode
            }).toQueryString(),
            onSuccess: function(transport) {
                var track_div_id = Controller.gbtracks.get(track_id).track_div_id;
                Balloon.prototype.hideTooltip(1);
                if (show_track == track_id){
                    Controller.rerender_track(track_id,false,false);
                } else {
                    if ($(track_div_id) != null) {
                        actually_remove(track_div_id);
                    }
                    Controller.update_sections(new Array(track_listing_id),null,null,true);
                }
            } // end onSuccess
        });
    },

    filter_subtrack:
    function(track_id, form_element) {

        new Ajax.Request(Controller.url, {
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
        new Effect.BlindDown(div_id);
    },

    reconfigure_plugin:
    function(plugin_action,plugin_track_id,pc_div_id,plugin_type,form_element,synchronous) {
        if (form_element==null)
            form_element = $("configure_plugin");
        else
            Element.extend(form_element);

	if (synchronous == null)
	    synchronous = false;

        new Ajax.Request(Controller.url, {
                method:     'post',
		asynchronous: !synchronous,
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
                    var e = $(track_listing_id);
                    e.hide();
                    e.setOpacity(0.3);
                    e.show();
                    Controller.update_sections(new Array(track_listing_id),'',1,false);
                }
	     } // end onSuccess
        });
    },

    plugin_authenticate:
    function(configuration_form,message_area) {
	message_area.innerHTML='<img src="'+this.button_url('spinner.gif')+'" />'+Controller.translate('WORKING');
	this.reconfigure_plugin('Configure',null,null,'authorizer',configuration_form,true);
	var remember = $('authenticate_remember_me').getValue() == 'on';
	new Ajax.Request(Controller.url, {
                method:     'post',
	        parameters: {
		    action:  'plugin_authenticate'
		},
		onSuccess: function (t) {
		    var results    = t.responseJSON;
		    if (results.userOK) {
			Balloon.prototype.hideTooltip(1);
			// the definition for this call is in login.js
			login_get_account(results.username,results.sessionid,remember,false);
		    }
		    else
			message_area.innerHTML='<div style="color:red">'+results.message+'</div>';
		}
	});
    },

    plugin_go:
    function(plugin_base,plugin_type,plugin_action,source) {
        if (plugin_type == 'annotator'){
            var select_box = document.pluginform.plugin;
            var track_name = select_box.options[select_box.selectedIndex].attributes.getNamedItem('track_name').value;

            this.add_track(track_name);
            Controller.update_sections(new Array(track_listing_id),null,null,false);
        } else if (plugin_type == 'dumper') {
            var loc_str = "?plugin="+plugin_base+";plugin_action="+encodeURI(plugin_action);
            loc_str += ';view_start=' + TrackPan.get_start();
            loc_str += ';view_stop='  + TrackPan.get_stop();
            if(source == 'config'){
                var form_element = $("configure_plugin");
                window.open(loc_str + ";" + form_element.serialize());
            } else{
                window.open(loc_str);
            }
        } else if (plugin_type == 'filter'){
            // Go doesn't do anything for filter
            return false; 
        } else if (plugin_type == 'finder'){
            document.searchform.plugin_find.value  = $F('plugin');
            document.searchform.force_submit.value = 1;
            document.searchform.submit();
        }
    }, // end plugin_go

    cancel_upload:
    function(destination, upload_id) {
        new Ajax.Updater(
            destination,
            document.URL,
            {
                method:    'post',
                parameters: {
                action: 'cancel_upload',
                upload_id: upload_id
            }
        });
    },

    // Utility methods *********************************
    show_error:
    function (message, details) {
        var outerdiv    = $('errordiv');
        var innerdiv    = $('errormsg');
        var detailsdiv  = $('errordetails');
        if (innerdiv != null) {
            var caption = detailsdiv.visible() ? Controller.translate('HIDE_DETAILS') : Controller.translate('SHOW_DETAILS');
            innerdiv.innerHTML = message +
            ' <span id="detailscaption" class="clickable" style="font-size:12pt" onClick="Controller.show_hide_errordetails()">'
            +caption
            +'</span>';
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
            caption.innerHTML=Controller.translate('SHOW_DETAILS');
            detailsdiv.hide();
        } else {
            caption.innerHTML=Controller.translate('HIDE_DETAILS');
            detailsdiv.show();
        }
    },
    
show_info_message:
    function (action,width) {
        if (width == null) width=300;
    var dim     = document.body.getDimensions();
    var info = $('info_container');
    if (info == null) {
        info        = new Element('div',{id:'info_container'});
        info.setStyle({position: 'absolute',
               zIndex:   100000,
               display:'none'});
        document.body.appendChild(info);

        var abs_container = new Element('div',{id:'abs_info_container'});
        info.appendChild(abs_container);

        var content = new Element('div',{id:'info_content'});
        abs_container.appendChild(content);
        var button = new Element('input',{type:'button',
                          style:'float:right',
                          id:'info_button',
                          value:this.translate('OK')});
        // button.insert('&nbsp;'); // needed to close tag
        button.observe('click',function(ev) {$('info_container').hide()});
        content.insert({after:button});
    }
    // double containment necessary to avoid IE zindex bug!
    $('info_container').setStyle( {
        position: 'absolute',
        backgroundColor: 'white',
            top:      '50px',
        left:     Math.round((dim.width-width)/4)+'px',
        zIndex:   10000,
        width:   width+'px'
        });
        $('abs_info_container').setStyle( {
        position: 'absolute',
        backgroundColor: 'white',
            top:      '0px',
        left:     '0px',
        border:   'double',
        padding: '5px',
        zIndex:  100001
        });
    new Ajax.Updater('info_content',
             document.URL,{ 
                 parameters: { action: action } ,
                 onSuccess: function (t) { $('info_container').show()}
    });
    },

    edit_upload_title:
    function(upload_name, title_element) {
        if (title_element == null)
            return true;
	Element.extend(title_element);
        title_element.setStyle({
            border: '2px',
	    cursor: 'text',
            inset:  'black',
            backgroundColor:'beige',
            padding:'5px 5px 5px 5px'
        });
	// var r = document.createRange();
        // r.selectNodeContents(title_element);
        // window.getSelection().addRange(r);
        Event.observe(title_element, 'keypress', this.set_upload_title);
        Event.observe(title_element, 'blur', this.set_upload_title);
    },

    set_upload_title:
    function(event) {
        var title_element = event.findElement();
        if (event.type == 'blur' || event.keyCode == Event.KEY_RETURN || event.keyCode == Event.KEY_ESC) {
            var file = title_element.up("div.custom_track").id;
            var title = title_element.innerHTML;
            title_element.update(new Element("img", {src: Controller.button_url('spinner.gif'), alt: Controller.translate('WORKING')}) );

	    if (event.keyCode == Event.KEY_ESC) { // backing out changes
		var sections = new Array(custom_tracks_id);
		if (using_database())  sections.push(community_tracks_id);
		Controller.update_sections(sections);
	    } else {
		new Ajax.Request(Controller.url, {
			method:      'post',
			    parameters:{  
			    action: 'set_upload_title',
				upload_id: file,
				title: title
				},
			    onSuccess: function(transport) {
			    var sections = new Array(custom_tracks_id, track_listing_id);
			    if (using_database()) sections.push(community_tracks_id);
			    Controller.update_sections(sections);
			}
		});
	    }
            title_element.stopObserving('keypress');
            title_element.stopObserving('blur');
            title_element.blur();
            return true;
        }
        return false;
    },

    edit_upload_track_key:
	function(upload_name, upload_label, key_element) {
        if (key_element == null)
            return true;
	Element.extend(key_element);
        key_element.setStyle({
            border: '2px',
	    cursor: 'text',
            inset:  'black',
            backgroundColor:'beige',
            padding:'5px 5px 5px 5px'
        });
	key_element.upload_name  = upload_name;
	key_element.upload_label = upload_label;
	key_element.onclick = null;
	Event.stopObserving(key_element);
        Event.observe(key_element, 'keypress', this.set_upload_track_key);
        Event.observe(key_element, 'blur',     this.set_upload_track_key);
    },

    set_upload_track_key:
	function(event) {
	    var key_element  = event.findElement();
	    var file  = key_element.upload_name;
	    var label = key_element.upload_label;
	    var value = key_element.innerHTML.stripTags();

	    // the following code is cut-and-paste from set_upload_title and is largely redundant
	    if (event.type == 'blur' || event.keyCode == Event.KEY_RETURN || event.keyCode == Event.KEY_ESC) {
		key_element.update(new Element("img", {src: Controller.button_url('spinner.gif'), alt: Controller.translate('WORKING')}) );
		if (event.keyCode == Event.KEY_ESC) { // backing out
		    var sections = new Array(custom_tracks_id);
		    if (using_database()) sections.push(community_tracks_id);
		    Controller.update_sections(sections);
		} else {
		    new Ajax.Request(Controller.url, {
			    method:      'post',
				parameters:{  
				action: 'set_upload_track_key',
				    upload_id: file,
				    label:     label,
				    key:       value
				    },
				onSuccess: function(transport) {
				  var new_key  = transport.responseText;
				  var sections = new Array(custom_tracks_id, track_listing_id);
				  if (using_database()) sections.push(community_tracks_id);
				  Controller.update_sections(sections);
				  //alert($(label+'_title').select('span.drag_region').innerHTML);
				  var titles = $(label+'_title').select('span.drag_region');
				  titles[0].innerHTML='<b>'+new_key+'</b>';
			    }
		    });
		}
		key_element.stopObserving('keypress');
		key_element.stopObserving('blur');
		key_element.blur();
		return true;
	    }
	    return false;
	},

    edit_upload_description:
    function(upload_name,container_element) {
        if (container_element == null)
            return true;
        container_element.setStyle({
            border: '2px',
	    cursor: 'text',
            inset:  'black',
            backgroundColor:'beige',
            padding:'5px 5px 5px 5px'
        });
        // var r = document.createRange();
        // r.selectNodeContents(container_element);
        // window.getSelection().addRange(r);
        Event.observe(container_element,'keypress',this.set_upload_description);
        Event.observe(container_element,'blur',this.set_upload_description);
    },

    set_upload_description:
    function(event) {
        var description_box = event.findElement();
        if (event.type=='blur' || event.keyCode==Event.KEY_RETURN) {
            var file = description_box.up("div.custom_track").id;
            var description = description_box.innerHTML;
            description_box.update(new Element("img", {src: Controller.button_url('spinner.gif'), alt: Controller.translate('WORKING')}) );
            new Ajax.Request(Controller.url, {
                method:      'post',
                parameters:{  
                    action: 'set_upload_description',
                    upload_id: file,
                    description: description
                },
                onSuccess: function(transport) {
                    var sections = new Array(custom_tracks_id);
                    if (using_database())
                        sections.push(community_tracks_id);
                    Controller.update_sections(sections);
                }
            });
            description_box.stopObserving('keypress');
            description_box.stopObserving('blur');
            description_box.blur();
            return true;
        }
        if (event.keyCode==Event.KEY_ESC) {
            description_box.update(new Element("img", {src: Controller.button_url('spinner.gif'), alt: "Working..."}) );
            var sections = new Array(custom_tracks_id);
            if (using_database())
                sections.push(community_tracks_id);
            Controller.update_sections(sections);
            description_box.stopObserving('keypress');
            description_box.stopObserving('blur');
            description_box.blur();
            return true;
        }
        return false;
    },

    // downloadUserTrackSource() is called to populate the user track edit field
    // with source or configuration data for the track
    downloadUserTrackSource:
    function (destination, fileid, sourceFile) {
        new Ajax.Request (
            document.URL, 
            {
                method: 'post',
                parameters: {
                    userdata_download: sourceFile,
                    track: fileid
                },
		onSuccess: function (t) { $(destination).value=t.responseText }
            }
        );
    },


    // This is really messed up and should be moved to ajax_upload.js
    _modifyUserTrackSource:
    function (param, statusElement, displayWhenDone) {
        var upload_id  = 'upload_' + Math.floor(Math.random() * 99999);
        param.upload_id = upload_id;
        new Ajax.Request(Controller.url, {
            method: 'post',
            parameters: param,
            onCreate: function() {
                if ($(statusElement) != null) {
                    $(statusElement).update();
                    $(statusElement).insert(new Element("div", {id: upload_id + "_form"}));
                    $(statusElement).insert(new Element("div", {id: upload_id + "_status"}));
                }
                startAjaxUpload(upload_id);
            },
            onSuccess: function (transport) {
                var r = transport.responseJSON;
                Controller.add_tracks(r.tracks,null,false,true);
                r.tracks.each(function(t) {
                 Controller.rerender_track(t,true,true);
                });
                var updater = Ajax_Status_Updater.get(upload_id);
                if (updater != null)
                    updater.stop();
                
                var sections = new Array(custom_tracks_id, track_listing_id);
				if (using_database())
					sections.push(community_tracks_id);
				Controller.update_sections(sections);
                if (displayWhenDone != null && displayWhenDone)
                    Controller.select_tab('main_page');
		},
	    onComplete: function (transport) { 
		    var updater = Ajax_Status_Updater.get(upload_id);
		    if (updater != null)       updater.stop();
		    if (statusElement != null) cleanRemove(statusElement);
		}
        });

    },

    // uploadUserTrackSource() is called to submit a user track edit field
    // to the server
    uploadUserTrackSource:
    function (sourceField, fileid, sourceFile, editElement) {
        this._modifyUserTrackSource(
            {
                action: 'modifyUserData',
                file: fileid,
                sourceFile: sourceFile,
                data: $F(sourceField)
            },
            editElement
        );
    },

    // mirrorTrackSource() is called to mirror a URL to a track
    mirrorTrackSource:
    function (sourceURL, fileid, statusElement, displayWhenDone, forcejson) {
	if (forcejson == null) forcejson=false;
        this._modifyUserTrackSource(
            {
                action:     'upload_file',
                mirror_url: sourceURL,
                overwrite: 1,
		forcejson: forcejson
            },
            statusElement,
            displayWhenDone
        );
    },

// monitor_upload is redundant and needs to be refactored
// the idea is to register a new upload
  monitor_upload:
  function (upload_id,upload_name) {
  	new Ajax.Request(Controller.url, {
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
  function (tab_id,animate) {
     if (this.tabs != null) {
	 this.tabs.select_tab(tab_id,animate);
     }
  },

					     
  wait_for_initialization:
  function (html, callback) {
      $('main').setOpacity(0.2);
      var html = '<div id="dialog_123" style="position:absolute; left:50px; top:50px; border:5px double black; background: wheat; z-index:100">'
                 + html
                 +'</div>';
      $('main').insert({before:html});
      if (callback) callback();
      $('main').setOpacity(1.0);
      $('dialog_123').remove();
  },

  // Looks up a key in the language table. If not found, checks the defaults table.
  // If the translation contains %s, substitutes additional parameters for each occurance of %s (in order)
  // Usage: Controller.translate(key, [...])
  translate:
  function () {
    var key = arguments[0];
    var result;
    if (typeof language_table !== undefined && language_table) { //If the language table exists
      if (language_table[key]) {
         result = language_table[key];
      } else if (default_language_table[key]) {
         result = default_language_table[key];
      } else {
         alert('The key "' + key + '" was not found in the translation table.');
      }
    } else {
      alert('The key "' + key + '" could not be translated because the translation table is not loaded.');
    }
    for (var i = 1; i < arguments.length; i++) {
      result = result.replace(/(%s)/i, arguments[i]);
    }
    return result;
  },

  make_image_link:
  function(type) {
    var url = '?make_image=' + type;
    url += ';view_start=' + TrackPan.get_start();
    url += ';view_stop='  + TrackPan.get_stop();
    url += ';view_width=' + TrackPan.width_no_pad;
    window.open(url);
  },

  gbgff_link:
  function(url) {
    url += ';q=' + TrackPan.ref + ':' + TrackPan.get_start() + '..' + TrackPan.get_stop();
    window.location.href = url;
  },

  bookmark_link:
  function() {
    var url = '?action=bookmark';
    url += ';view_start=' + TrackPan.get_start();
    url += ';view_stop='  + TrackPan.get_stop();
    window.location.href = url;
  },
  
  get_sharing:
  function(event, url) {
    GBox.showTooltip(event, url);
	Controller.update_sections(new Array(custom_tracks_id));
  }

});

var Controller = new GBrowseController; // singleton

function using_database() {
	return ($(community_tracks_id))? true : false;
}

function initialize_page() {

    if (Controller == null) Controller = new GBrowseController;

    // This oddity prevents ?id=logout from appearing in the url box.
    // Otherwise whenever user reloads he is logged out :-(
    var index;
    if ((index = location.href.indexOf('?id=logout')) >= 0)
	location.href=location.href.substr(0,index);

    checkSummaries();
    // These statements initialize the tabbing
    var tabs = $$("div.tabbody").collect( function(element) {
	    return element.id;
	});
    Controller.tabs = new TabbedSection(tabs);

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

// set the colors for the rubberband regions
function set_dragunits(unit,divider) {
    if (unit == null)    unit    = 'bp';
    if (divider == null) divider = 1;
    if (overviewObject != null) {
	overviewObject.unit    = unit;
        overviewObject.divider = divider;
    }
    if (regionObject != null) {
	regionObject.unit      = unit;
	regionObject.divider   = divider;
    }
    if (detailsObject != null) {
	detailsObject.unit    = unit;
	detailsObject.divider = divider;
    }
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

function create_drag (div_name) {
   GlobalDrag = div_name;
   Sortable.create(
		  div_name,
		  {
		      tag:     'div',
		      constraint:  'vertical',
  		      only:    'track',
		      handle:  'drag_region',
		      scroll:   window,
		      onUpdate: function() {
		      var items   = $(div_name).select('[class="track"]');
		      var ids     = items.map(function(e){return e.id});
		      ids         = ids.map(function(i) {return 'label[]='+escape(i.sub(/^track_/,''))});
		      var postData= ids.join('&')+';action=change_track_order';
		      new Ajax.Request(document.URL,{method:'post',postBody:postData});
		    }
		  }
		 );
}

