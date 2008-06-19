/*

 controller.js -- The GBrowse controller object

 Lincoln Stein <lincoln.stein@gmail.com>
 $Id: controller.js,v 1.7 2008-06-19 21:09:57 mwz444 Exp $

*/

var Controller;        // singleton
var SegmentObservers = new Hash();


var GBrowseController = Class.create({

	initialize: function () {
        this.periodic_updaters = new Array();
	},

	updateCoordinates: function (action) {
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
                            //alert ("success "+detail_div_id);
                            detail_div = document.getElementById(detail_div_id);
                            if (transport.responseText.substring(0,18) == "<!-- AVAILABLE -->"){
                                detail_div.innerHTML = transport.responseText;
                                Controller.periodic_updaters[detail_div_id].stop();
                                reset_after_track_load();
                            }
                            else if (transport.responseText.substring(0,16) == "<!-- EXPIRED -->"){
                                detail_div.innerHTML = transport.responseText;
                                Controller.periodic_updaters[detail_div_id].stop();
                                reset_after_track_load();
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
