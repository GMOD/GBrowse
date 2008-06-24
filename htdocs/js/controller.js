/*

 controller.js -- The GBrowse controller object

 Lincoln Stein <lincoln.stein@gmail.com>
 $Id: controller.js,v 1.9 2008-06-24 03:44:10 mwz444 Exp $

*/

var Controller;        // singleton
var SegmentObservers      = new Hash();
var UpdateOnLoadObservers = new Hash();
var TrackImages           = new Hash();


var GBrowseController = Class.create({

	initialize: function () {
        this.periodic_updaters = new Array();
	},

	updateCoordinates: function (action) {

        //Grey out image
        TrackImages.keys().each(
            function(image_id) {
                $(image_id).setOpacity(0.3);
            }
        );

        this.periodic_updaters[this.count] = this.count;
	    new Ajax.Request('#',{
		    method:     'post',
   		    parameters: {navigate: action},
		    onSuccess: function(transport) {
                var results = transport.responseJSON;
                var segment = results.segment;
                var track_keys = results.track_keys;
                SegmentObservers.keys().each(
                              function(e) {
                              $(e).fire('model:segmentChanged',{segment: segment, track_keys: track_keys});
                              }
                              );
		    }
            
		}
		);
	}
    }
);

function initialize_page () {
    Controller = new GBrowseController; // singleton

    //event handlers
    SegmentObservers.set('page_title',1);
    $('page_title').observe('model:segmentChanged',function(event) {
	    //	    this.innerHTML='<img src="/images/buttons/ajax-loader.gif" />';
	    new Ajax.Updater(this,'#',{
		    parameters: {update: this.id}
	    });
	}
	);
    new Ajax.Request('#',{
        method:     'post',
        parameters: {first_render: 1},
        onSuccess: function(transport) {
            var results = transport.responseJSON;
            var segment = results.segment;
            var track_keys = results.track_keys;
            UpdateOnLoadObservers.keys().each(
                function(e) {
                    $(e).fire('model:segmentChanged',{segment: segment, track_keys: track_keys});
                }
            );
        }
    }
    );


/*    var elements = ['landmark_search_field','overview_panels','detail_panels'];
    elements.each(function(el) {
        SegmentObservers.set(el,1);
	$(el).observe('model:segmentChanged',function(event) {
	    new Ajax.Request('#',{
		    method:     'post',
		    parameters: {update: this.id},
		    onSuccess:  function(transport) {
			if ($(el).value != null) {
			    $(el).value = transport.responseText;
			}
			else {
			    $(el).innerHTML = transport.responseText;
			}
		    }
	    })
	});
  });
*/

}

function register_track ( detail_div_id,detail_image_id ) {
    SegmentObservers.set(detail_div_id,1);
    UpdateOnLoadObservers.set(detail_div_id,1);
    TrackImages.set(detail_image_id,1);
    //alert("registering track "+detail_div_id);
    $(detail_div_id).observe('model:segmentChanged',function(event) {
	    var track_key = event.memo.track_keys[detail_div_id];
        //alert ("track_changed "+detail_div_id);
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
                            track_key: track_key,
                            retreive_track: detail_div_id,
                            image_width: track_image.width,
                            image_height: track_image.height,
                            image_id: detail_image_id,
                        },
                        onSuccess: function(transport) {
                            //alert ("success "+detail_div_id +" "+transport.responseText.substring(0,10));
                            detail_div = document.getElementById(detail_div_id);
                            if (transport.responseText.substring(0,18) == "<!-- AVAILABLE -->"){
                                detail_div.innerHTML = transport.responseText;
                                Controller.periodic_updaters[detail_div_id].stop();
                                reset_after_track_load();
                            }
                            else if (transport.responseText.substring(0,16) == "<!-- EXPIRED -->"){
                                Controller.periodic_updaters[detail_div_id].stop();
                                reset_after_track_load();
                            }
                            else {
                                // Manually stop the updater from modifying the element
                                var p_updater = Controller.periodic_updaters[detail_div_id];
                                var decay = p_updater.decay;
                                p_updater.stop();
                                p_updater.decay = decay * p_updater.options.decay;
                                p_updater.timer = p_updater.start.bind(p_updater).delay(p_updater.decay * p_updater.frequency);
                            }
                        }
                     }
                );
        }
	}
	);
}

// This may be a little overkill to run these after every track update but
// since there is no "We're completely done with all the track updates for the
// moment" hook, I don't know of another way to make sure the tracks become
// draggable again
function reset_after_track_load ( ) {
    create_drag('overview_panels','track');
    create_drag('detail_panels','track');
}
