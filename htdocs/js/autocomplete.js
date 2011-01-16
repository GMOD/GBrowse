var Autocomplete1;
var Autocomplete2;

function initAutocomplete() {
    if ($('landmark_search_field'))
	 Autocomplete1 =
	 	 new Ajax.Autocompleter(
	                 "landmark_search_field",
                         "autocomplete_choices",
                    	 document.URL,
                         {
			 // indicator:          'indicator1',
			  frequency: 0.2,
                          parameters:         'action=autocomplete',
                          paramName:          'prefix',
			  minChars:           2
                         }
	 );

    if ($('public_search_keyword'))
	 Autocomplete2 =
	 	 new Ajax.Autocompleter(
	                 "public_search_keyword",
                         "autocomplete_upload_filter",
                    	 document.URL,
                         {
			     //			  indicator:          'indicator2',
			  frequency: 0.2,
                          parameters:         'action=autocomplete_upload_search',
                          paramName:          'prefix',
			  minChars:           3,
			  // don't know why scriptaculous built-in functionality isn't working
			  // but characters are getting duplicated in input field
			  updateElement: function(t) {
				 var stripped = t.innerHTML.replace(/(<([^>]+)>)/ig,"");
				 $('public_search_keyword').value=stripped;
			     }
                         }
	 );

    var group_fields = document.body.select('input.username_entry');
    group_fields.each(function(f) {
	    var id = f.id;
	    new Ajax.Autocompleter(
				   id,
				   id + "_choices",
                    	 document.URL,
                         {
			  frequency: 0.2,
                          parameters:         'action=autocomplete_user_search',
                          paramName:          'prefix',
			  minChars:           3,
			  updateElement: function(t) {
				 var stripped = t.innerHTML.replace(/(<([^>]+)>)/ig,"").replace(/&gt;/,'>').replace(/&lt;/,'<');
				 $(id).value=stripped;
			     }
                         })});
}


