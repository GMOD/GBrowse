# do not remove the { } from the top and bottom of this page!!!
{
   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => 'Genome browser',

   SEARCH_INSTRUCTIONS => <<END,
Search using a sequence name, gene name,
locus%s, or other landmark. The wildcard
character * is allowed.
END

   NAVIGATION_INSTRUCTIONS => <<END,
To center on a location, click the ruler. Use the Scroll/Zoom buttons
to change magnification and position. To save this view,
<a href="%s">bookmark this link.</a>
END

   EDIT_INSTRUCTIONS => <<END,
Edit your uploaded annotation data here.
You may use tabs or spaces to separate fields,
but fields that contain whitespace must be contained in
double or single quotes.
END

   SHOWING_FROM_TO => 'Showing %s from %s, positions %s to %s',

   LANDMARK => 'Landmark or Region',

   GO       => 'Go',

   FIND     => 'Find',

   DUMP     => 'Dump',

   ANNOTATE     => 'Annotate',

   SCROLL   => 'Scroll/Zoom',

   RESET    => 'Reset',

   DOWNLOAD_FILE    => 'Download File',

   DOWNLOAD_DATA    => 'Download Data',

   DOWNLOAD         => 'Download',

   DISPLAY_SETTINGS => 'Display Settings',

   TRACKS   => 'Tracks',

   EXTERNAL_TRACKS => '(External tracks italicized)',

   EXAMPLES => 'Examples',

   HELP     => 'Help',

   HELP_FORMAT => 'Help with File Format',

   CANCEL   => 'Cancel',

   ABOUT    => 'About...',

   REDISPLAY   => 'Redisplay',

   CONFIGURE   => 'Configure...',

   EDIT       => 'Edit File...',

   DELETE     => 'Delete File',

   EDIT_TITLE => 'Enter/Edit Annotation data',

   IMAGE_WIDTH => 'Image Width',

   SET_OPTIONS => 'Set Track Options...',

   UPDATE      => 'Update Image',

   DUMPS       => 'Dumps, Searches and other Operations',

   DATA_SOURCE => 'Data Source',

   UPLOAD_TITLE=> 'Upload your own annotations',

   UPLOAD_FILE => 'Upload a file',

   BROWSE      => 'Browse...',

   UPLOAD      => 'Upload',

   REMOTE_TITLE => 'Add remote annotations',

   REMOTE_URL   => 'Enter Remote Annotation URL',

   UPDATE_URLS  => 'Update URLs',

   PRESETS      => '--Choose Preset URL--',

   FILE_INFO    => 'Last modified %s.  Annotated landmarks: $s',

   FOOTER_1     => <<END,
Note: This page uses cookie to save and restore preference information.
No information is shared.
END

   FOOTER_2    => 'Generic genome browser version %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => 'The following %d regions match your request.',

   MATCHES_ON_REF => 'Matches on %s',

   SEQUENCE        => 'sequence',

   SCORE           => 'score=%s',

   NOT_APPLICABLE => 'n/a',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => 'Settings for %s',

   UNDO     => 'Undo Changes',

   REVERT   => 'Revert to Defaults',

   REFRESH  => 'Refresh',

   CANCEL_RETURN   => 'Cancel Changes and Return...',

   ACCEPT_RETURN   => 'Accept Changes and Return...',

   OPTIONS_TITLE => 'Track Options',

   SETTINGS_INSTRUCTIONS => <<END,
The <i>Show</i> checkbox turns the track on and off. The
<i>Compact</i> option forces the track to be condensed so that
annotations will overlap. The <i>Expand</i> and <i>Hyperexpand</i>
options turn on collision control using slower and faster layout
algorithms. The <i>Expand</i> &amp; <i>label</i> and <i>Hyperexpand
&amp; label</i> options force annotations to be labeled. If
<i>Auto</i> is selected, the collision control and label options will
be set automatically if space permits. To change the track order use
the <i>Change Track Order</i> popup menu to assign an annotation to a
track. To limit the number of annotations of this type shown, change
the value of the <i>Limit</i> menu.
END

   TRACK  => 'Track',

   TRACK_TYPE => 'Track Type',

   SHOW => 'Show',

   FORMAT => 'Format',

   LIMIT  => 'Limit',

   ADJUST_ORDER => 'Adjust Order',

   CHANGE_ORDER => 'Change Track Order',

   AUTO => 'Auto',

   COMPACT => 'Compact',

   EXPAND => 'Expand',

   EXPAND_LABEL => 'Expand & Label',

   HYPEREXPAND => 'Hyperexpand',

   HYPEREXPAND_LABEL =>'Hyperexpand & label',

   NO_LIMIT    => 'No limit',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => 'Close this window',

   TRACK_DESCRIPTIONS => 'Track Descriptions & Citations',

   BUILT_IN           => 'Tracks Built into this Server',

   EXTERNAL           => 'External Annotation Tracks',

   ACTIVATE           => 'Please activate this track in order to view its information.',

   NO_EXTERNAL        => 'No external features loaded.',

   NO_CITATION        => 'No additional information available.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => 'About %s',

 BACK_TO_BROWSER => 'Back to Browser',

 PLUGIN_SEARCH_1   => '%s (via %s search)',

 PLUGIN_SEARCH_2   => '&lt;%s search&gt;',

 CONFIGURE_PLUGIN   => 'Configure',

 BORING_PLUGIN => 'This plugin has no extra configuration settings.',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => 'The landmark named <i>%s</i> is not recognized. See the help pages for suggestions.',

 TOO_BIG   => 'Detailed view is limited to %s bases.  Click in the overview to select a region %s bp wide.',

 PURGED    => "Can't find the file named %s.  Perhaps it has been purged?.",

 NO_LWP    => "This server is not configured to fetch external URLs.",

 FETCH_FAILED  => "Could not fetch %s: %s.",

 TOO_MANY_LANDMARKS => '%d landmarks.  Too many to list.',

 SMALL_INTERVAL    => 'Resizing small interval to %s bp',

};
