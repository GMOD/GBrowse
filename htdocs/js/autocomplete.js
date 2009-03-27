var Autocomplete;

function initAutocomplete() {
	 Autocomplete =
	 	 new Ajax.Autocompleter(
	                 "landmark_search_field",
                         "autocomplete_choices",
                    	 document.URL,
                         {indicator:          'indicator1',
                          parameters:         'action=autocomplete',
                          paramName:          'autocomplete',
			  minChars:           2
                         }
	 );
}


