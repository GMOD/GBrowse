var Autocomplete;

function initAutocomplete() {
	 Autocomplete =
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
}


