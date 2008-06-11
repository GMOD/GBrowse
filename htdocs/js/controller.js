/*

 controller.js -- The GBrowse controller object

 Lincoln Stein <lincoln.stein@gmail.com>
 $Id: controller.js,v 1.3 2008-06-11 23:27:08 lstein Exp $

*/

var Controller;        // singleton
var SegmentObservers = new Hash();


var GBrowseController = Class.create({

	initialize: function () {
	},

	updateCoordinates: function (action) {
	    new Ajax.Request('#',{
		    method:     'post',
   		    parameters: {navigate: action},
		    onSuccess: function(transport) {
			var results = transport.responseJSON;
			var segment = results.segment;
			SegmentObservers.keys().each(
					      function(e) {
						  $(e).fire('model:segmentChanged',segment);
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

    var elements = ['landmark_search_field','overview_panels','detail_panels'];
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

}

