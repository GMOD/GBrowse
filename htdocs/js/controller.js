/*

 controller.js -- The GBrowse controller object

 Lincoln Stein <lincoln.stein@gmail.com>
 $Id: controller.js,v 1.2 2008-06-11 23:08:16 lstein Exp $

*/


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
			$$('.segmentObserver').each(
					      function(e) {
						  e.fire('model:segmentChanged',segment);
					      }
					      );
		    }
		}
		);
	}
    }
);

var Controller; // singleton

function initialize_page () {
    Controller = new GBrowseController; // singleton

    //event handlers
    $('page_title').addClassName('segmentObserver');
    $('page_title').observe('model:segmentChanged',function(event) {
	    //	    this.innerHTML='<img src="/images/buttons/ajax-loader.gif" />';
	    new Ajax.Updater(this,'#',{
		    parameters: {update: this.id}
	    });
	}
	);

    var elements = ['landmark_search_field','overview_panels','detail_panels'];
    elements.each(function(el) {
        $(el).addClassName('segmentObserver');
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

