# do not remove the { } from the top and bottom of this page!!!
{

 CHARSET =>   'ISO-8859-1',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => 'Genome browser',

   SEARCH_INSTRUCTIONS => <<END,
<b>Search</b> using a sequence name, gene name,
locus%s, or other landmark. The wildcard
character * is allowed.
END

   NAVIGATION_INSTRUCTIONS => <<END,
<br><b>Navigate</b> by clicking one of the rulers to center on a location, or click and drag to
select a region. Use the Scroll/Zoom buttons to change magnification
and position.
END

   EDIT_INSTRUCTIONS => <<END,
Edit your uploaded annotation data here.
You may use tabs or spaces to separate fields,
but fields that contain whitespace must be contained in
double or single quotes.
END

   SHOWING_FROM_TO => '%s from %s:%s..%s',

   CURRENTLY_SHOWING => '(Currently showing %s)',

   INSTRUCTIONS      => 'Instructions',

   HIDE              => 'Hide',

   FILE              => 'File',

   SHOW              => 'Show',

   SHOW_HEADER       => 'Show banner',

   HIDE_HEADER       => 'Hide banner',

   LANDMARK => 'Landmark or Region',

   BOOKMARK => 'Bookmark this',

   CHROM_SIZES => 'Get chrom sizes',

   EXPORT => 'Export as...',

   IMAGE_LINK => '...low-res PNG image',

   SVG_LINK   => '...editable SVG image',

   PDF_LINK   => '...high-res PDF',
   
   DUMP_GFF   => '...GFF annotation table',

   DUMP_SEQ   => '...FASTA sequence file',

   FILTER     => 'Filter',

   TIMEOUT  => <<'END',
Your request timed out.  You may have selected a region that is too large to display.
Either turn off some tracks or try a smaller region.  If you are experiencing persistent
timeouts, please press the red "Reset" button.
END

   GO       => 'Go',

   FIND     => 'Find',

   SEARCH   => 'Search',

   DUMP     => 'Download',

   HIGHLIGHT   => 'Highlight',

   ANNOTATE     => 'Annotate',

   SCROLL   => 'Scroll/Zoom',

   RESET    => 'Reset to defaults',

   FLIP     => 'Flip',

   DOWNLOAD_FILE    => 'Download File',

   DOWNLOAD         => 'Download',

   DISPLAY_SETTINGS => 'Display Settings',

   TRACKS   => 'Tracks',
   
  
# FAVORITE MENU LINKS
   FAVORITES => 'Show Favorites Only',		
    
   SHOWALL   => 'Show Favorites and Others',

   SHOW_ACTIVE => 'Show Active Tracks Only',

   SHOW_ACTIVE_INACTIVE => 'Show Active & Inactive Tracks',

   REFRESH_FAV   => 'Refresh Favorites',
    
   CLEAR_FAV     => 'Clear All Favorites',

   SHOW_ACTIVE_TRACKS     => 'Show Active Tracks Only',

   ADDED_TO     => 'Add track to favorites',

#############
   
   SNAPSHOT_FORM   => 'Snapshot Name',

   CURRENT_SNAPSHOT => 'Current Snapshot:',

   TIMESTAMP      => 'Snapshot Timestamp [GMT]',

   SNAPSHOT_SELECT => 'Snapshots',

   SAVE_SNAPSHOT   => 'Save Snapshot',

   LOAD_SNAPSHOT   => 'Load Snapshot',

   SELECT_TRACKS   => 'Select Tracks',

   TRACK_SELECT   => 'Search for Specific Tracks',

   TRACK_NAME     => 'Track name',

   EXTERNAL_TRACKS => '<i>External tracks italicized</i>',

   OVERVIEW_TRACKS => '<sup>*</sup>Overview track',

   REGION_TRACKS => '<sup>**</sup>Region track',

   EXAMPLES => 'Examples',

   REGION_SIZE => 'Region Size (bp)',

   HELP     => 'Help',

   HELP_WITH_BROWSER     => 'Help with this browser',

   HELP_FORMAT_UPLOAD => 'Help with uploading custom tracks',

   CANCEL   => 'Cancel',

   ABOUT    => 'About GBrowse...',

   ABOUT_DSN    => 'About this database...',

   ABOUT_ME    => 'Show my user ID...',

   ABOUT_NAME   => 'About <i>%s</i>...',

   REDISPLAY   => 'Redisplay',

   CONFIGURE   => 'Configure...',

   SUBTRACK_INSTRUCTIONS   => 'Select the tracks you wish to display. Sort the tracks by clicking on the column headings, or by clicking and dragging rows into position.',

   SELECT_SUBTRACKS   => 'showing %d/%d subtracks',

   EDIT       => 'Edit File...',

   DELETE     => 'Delete File',

   EDIT_TITLE => 'Enter/Edit Annotation data',

   IMAGE_WIDTH => 'Image Width',

   BETWEEN     => 'Between',

   BENEATH     => 'Beneath',

   LEFT        => 'Left',

   RIGHT       => 'Right',

   TRACK_NAMES => 'Track Name Table',

   ALPHABETIC  => 'Alphabetic',

   VARYING     => 'Varying',

   SHOW_GRID    => 'Show grid',

   SET_OPTIONS => 'Configure tracks...',

   CLEAR_HIGHLIGHTING => 'Clear highlighting',

   CLEAR       => 'Clear',

   UPDATE      => 'Update',

   UPDATE_SETTINGS => 'Update Appearance',

   DUMPS       => 'Reports &amp; Analysis',

   DATA_SOURCE => 'Data Source',

   UPLOADED_TRACKS => 'Custom Tracks',

   UPLOAD_TITLE=> 'Upload your own data',

   UPLOAD_FILE => 'Upload a track file',

   MIRROR_FILE  => 'Fetch track file from this URL',

   IMPORT_TRACK => 'Import a track URL',

   NEW_TRACK    => 'Create a new track',

   FROM_TEXT    => 'From text',

   FROM_FILE    => 'From a file',

   FROM_URL    => 'From a URL',

   REMOVE       => 'Remove',

   KEY_POSITION => 'Key position',

   UPLOAD      => 'Upload',
   
   IMPORT      => 'Import',
   
   MIRROR      => 'Mirror',

   NEW         => 'New...',

   REMOTE_TITLE => 'Add remote annotations',

   #ipad
   IPAD_BALLOON => '\nTap feature again to see more details',
   #

   REMOTE_URL   => 'Enter remote track URL',

   UPDATE_URLS  => 'Update',

   PRESETS      => '--Choose Preset URL--',

   FEATURES_TO_HIGHLIGHT => 'Highlight feature(s) (feature1 feature2...)',

   REGIONS_TO_HIGHLIGHT => 'Highlight regions (region1:start..end region2:start..end)',

   FEATURES_TO_HIGHLIGHT_HINT => 'Hint: use feature@color to select the color, as in \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => 'Hint: use region@color to select the color, as in \'Chr1:10000..20000@lightblue\'',

   FEATURES_CLIPPED => 'Showing %s of %s features',

   FEATURES_CLIPPED_MAX => 'Showing %s of >%s features',

   FILE_INFO    => 'Last modified %s.  Annotated landmarks: %s',

   FOOTER_1     => <<END,
Note: This page uses cookies to save and restore preference information.
No information is shared.
END

   FOOTER_2    => 'Generic genome browser version %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => 'The following %d regions match your request.',

   POSSIBLE_TRUNCATION  => 'Search results are limited to %d hits; list may be incomplete.',

   MATCHES_ON_REF => 'Matches on %s',

   SEQUENCE        => 'sequence',

   SCORE           => 'score=%s',

   NOT_APPLICABLE => 'n/a',

   BP             => 'bp',

   NAME           => 'Name',
   TYPE           => 'Type',
   SUBTYPE         => 'subtype',
   DESCRIPTION    => 'Description',
   POSITION       => 'Position',
   SCORE          => 'Match Score',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => 'Settings for %s',

   UNDO     => 'Undo Changes',

   REVERT   => 'Revert to Defaults',

   REFRESH  => 'Refresh',

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

   LIMIT  => 'Max. features to show',

   ADJUST_ORDER => 'Adjust Order',

   CHANGE_ORDER => 'Change Track Order',

   AUTO => 'Auto',

   COMPACT => 'Compact',

   EXPAND => 'Expand',

   EXPAND_LABEL => 'Expand & Label',

   HYPEREXPAND => 'Hyperexpand',

   NO_LIMIT    => 'No limit',

   OVERVIEW    => 'Overview',

   EXTERNAL    => 'External',

   ANALYSIS    => 'Analysis',

   GENERAL     => 'General',

   DETAILS     => 'Details',

   REGION      => 'Region',

   ALL_ON      => 'All on',

   ALL_OFF     => 'All off',

   #--------------
   # HELP PAGES
   #--------------

   OK                 => 'OK',

   CLOSE_WINDOW => 'Close this window',

   EXTERNAL           => 'External Annotation Tracks',

   ACTIVATE           => 'Please activate this track in order to view its information.',


   #--------------
   # PLUGIN PAGES
   #--------------

 BACK_TO_BROWSER => 'Back to Browser',

 PLUGIN_SEARCH_1   => '%s (via %s search)',

 PLUGIN_SEARCH_2   => '&lt;%s search&gt;',

 CONFIGURE_PLUGIN   => 'Configure',

 BORING_PLUGIN => 'This plugin has no extra configuration settings.',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => 'The landmark named <i>%s</i> is not recognized. See the help pages for suggestions.',

 TOO_BIG   => 'Detailed view is limited to %s. Click and drag on one of the scalebars to make a smaller selection.',

 NO_LWP    => "This server is not configured to fetch external URLs.",

 FETCH_FAILED  => "Could not fetch %s: %s.",

 TOO_MANY_LANDMARKS => '%d landmarks.  Too many to list.',

 SMALL_INTERVAL    => 'Resizing small interval to %s bp',

 NO_SOURCES        => 'There are no readable data sources configured.  Perhaps you do not have permission to view them.',

 ADD_YOUR_OWN_TRACKS => 'Add custom tracks',

 ADD_DESCRIPTION    => 'Click to add a description',
 ADD_TITLE          => 'Click to edit the title',
 NO_DESCRIPTION     => 'No description',

 CONFIGURATION     => 'Configuration',

 BACKGROUND_COLOR  => 'Fill color',

 FG_COLOR          => 'Line color',

 HEIGHT           => 'Height',

 PACKING          => 'Spacing',

 GLYPH            => 'Shape',

 XYPLOT_TYPE      => 'plot style',

 WHISKERS_TYPE      => 'whiskers subtype',

 BICOLOR_PIVOT    => 'Switch colors when value crosses',

 BICOLOR_PIVOT_VALUE    => 'Switch point value',

 BICOLOR_PIVOT_POS_COLOR    => 'Color above switch point',

 BICOLOR_PIVOT_NEG_COLOR    => 'Color below switch point',

 WHISKER_MEAN_COLOR    => 'Color from 0 to mean value',

 WHISKER_STDEV_COLOR    => 'Color from mean to stdev value',

 WHISKER_MAX_COLOR    => 'Color from stdev to min/max value',

 AUTOSCALING      => 'Y-axis scaling',

 SD_MULTIPLES     => 'Number of standard deviations (SD) to show',

 SCALING          => 'Fixed Y-axis range',

 SCALE_MIN        => 'Minimum scale value',

 SCALE_MAX        => 'Maximum scale value',

 MIN              => 'Min',
 MAX              => 'Max',

 SHOW_VARIANCE    => 'Show variance band',

 APPLY_CONFIG     => 'Apply config when view between',

 SHOW_SUMMARY     => 'Show summary when region >',

 FEATURE_SUMMARY     => 'Feature Density Summary',

 LINEWIDTH        => 'Line width',

 STRANDED         => 'Show strand',

 DEFAULT          => '(default)',

 DYNAMIC_VALUE    => 'Dynamically calculated',

 CHANGE           => 'Change',

 CACHE_TRACKS      => 'Cache tracks',

 SHOW_TOOLTIPS     => 'Show tooltips',

 SEND_TO_GALAXY    => 'Export to Galaxy',

 NO_DAS            => 'Installation error: Bio::Das module must be installed for DAS URLs to work. Please inform this site\'s webmaster.',

 SHOW_OR_HIDE_TRACK => '<b>Show or hide this track</b>',

 KILL_THIS_TRACK    => '<b>Turn off this track</b>',

 CONFIGURE_THIS_TRACK   => '<b>Configure this track</b>',

 DOWNLOAD_THIS_TRACK   => '<b>Download this track</b>',

 ABOUT_THIS_TRACK   => '<b>About this track</b>',

 SUBTRACKS_SHOWN    => 'This track contains selectable subtracks. Click to modify the selection or change subtrack order.',

 SHOWING_SUBTRACKS  => '(<i>Showing %d of %d subtracks</i>)',

 OVERLAP            => 'Semi-transparent overlap',

 AUTO_COLORS        => 'Set colors automatically',

 SHARE_THIS_TRACK   => '<b>Share this track</b>',

 SHARE_ALL          => 'Share these tracks',

 SHARE              => 'Share %s',

 SHARE_INSTRUCTIONS_BOOKMARK => <<END,
To <b>share</b> this track with another user, copy the URL below and
send it to him or her.
END

 SHARE_INSTRUCTIONS_ONE_TRACK => <<END,
To <b>export</b> this track to a different GBrowse genome browser,
first copy the URL below, then go to the other GBrowse, 
select the "Upload and Share Tracks" tab, click the "From a URL" link
and paste in the URL.
END

 SHARE_INSTRUCTIONS_ALL_TRACKS => <<END,
To export all currently selected tracks to another GBrowse genome
browser, first copy the URL below, then go to the other GBrowse,
select the "Upload and Share Tracks" tab, click the "From a URL" link
and paste in the URL.
END

 SHARE_DAS_INSTRUCTIONS_ONE_TRACK => <<END,
To export this track with another genome browser using 
the <a href="http://www.biodas.org" target="_new">
Distributed Annotation System (DAS)</a> first copy the URL below, 
then go to the other browser and enter it as a new DAS source.
<i>Quantitative tracks ("wiggle" files) and uploaded files can not
be shared using DAS.</i>
END

 SHARE_DAS_INSTRUCTIONS_ALL_TRACKS => <<END,
To export all currently selected tracks with another genome browser
using the <a href="http://www.biodas.org" target="_new"> Distributed
Annotation System (DAS)</a> first copy the URL below, then go to the
other browser and enter it as a new DAS source. <i>Quantitative tracks
("wiggle" files) and uploaded files can not be shared using DAS.</i>
END

 SHARE_CUSTOM_TRACK_NO_CHANGE => <<END,
This is a track from one of your custom uploads, it is using <b>%s</b>
permissions, so it can be shared.
END

 SHARE_CUSTOM_TRACK_CHANGED => <<END,
This is a track from one of your custom uploads, its permissions have
been changed to <b>%s</b>, so it can now be shared.
END

 SHARE_SHARED_TRACK => <<END,
This track is another user\'s custom uploads; it is shared under a <b>%s</b>
policy, so you are free to send the link to other users.
END

 SHARE_GROUP_EMAIL_SUBJECT => <<END,
Track sharing notification from the %s browser
END

 SHARE_GROUP_EMAIL => <<END,
The user named %s has shared some tracks with you. They will appear in your "Custom Tracks" section the next time you log into %s. To see the shared track(s) now, click on %s.

Additional information about the shared tracks follows:

  Upload name:        %s
  Upload description: %s
  Track names:        %s

If you wish to remove these tracks from your session, go to "Custom Tracks" and click on the '[X]' next to the upload name. To add it back to your session, click on %s.
END

 OTHER_SHARE_METHODS => <<END,
You can also share it with another user by setting its permissions to
<b>public</b> and giving them this link or letting them search for the
track by name, or by changing its permissions to <b>group</b> and adding
the user you want by username. To do this, select the "Custom Tracks"
page and choose the sharing policy you want with the drop-down menu in
the "sharing" section, then type the user's name or ID in the input
field provided.
END

 CANT_SHARE     => <<END,
Sorry, this track is owned by another user who has only allowed access to
a limited group of other users. Since it's not yours, you can't share it
with anyone else. In order to share this track, you'll have to ask them
for permission.
END

    MAIN_PAGE             => 'Browser',
    CUSTOM_TRACKS_PAGE    => 'Custom Tracks',
    COMMUNITY_TRACKS_PAGE => 'Community Tracks',
    SETTINGS_PAGE         => 'Preferences',

    DOWNLOAD_TRACK_DATA_REGION => 'Download track data across region %s',
    DOWNLOAD_TRACK_DATA_CHROM => 'Download track data across ENTIRE chromosome %s',
    DOWNLOAD_TRACK_DATA_ALL => 'Download ALL DATA for this track',

   #-------------------------
   # LOGIN/ACCOUNT MANAGEMENT
   #-------------------------

   FORGOT_MY_PASSWORD        => 'Forgot my password',
   EMAIL_MY_PASSWORD         => 'E-mail my password',
   EDIT_ACCOUNT_DETAILS      => '%s: Edit account details',
   CONTINUE                  => 'Continue',
   HAVE_OPENID               => 'Have an OpenID?',
   WITH_OPENID               => 'with your OpenID',
   SIGN_IN                   => 'Sign in',
   OPENID_PROMPT             => "Select your OpenID provider's icon from the list below, or type your OpenID into the text box.",
   DONT_HAVE_OPENID          => 'Don\'t have an OpenID?',
   GO_BACK                   => 'Go Back.',
   ALL_FIELDS_REQUIRED       => 'All fields are required.',
   PASSWORDS_DO_NOT_MATCH    => 'Passwords do not match.',
   LOG_IN                    => 'Log In',
   CHANGE_MY_EMAIL           => 'Change my E-mail',
   CHANGE_MY_NAME            => 'Change my Full Name',
   CHANGE_MY_PASSWORD        => 'Change my Password',
   ADD_OPENID                => 'Add OpenID to Account',
   REMOVE_OPENID             => 'Remove OpenId from Account',
   LIST_REMOVE_OPENIDS       => 'List/Remove OpenIDs',
   NEED_OPENID_TO_ACCESS     => 'Sorry, but you need at least one active OpenID associated with this account in order to access %s.',
   DELETE_MY_ACCOUNT         => 'Delete My Account',
   USERNAME                  => 'Username:',
   REALNAME                  => 'Your full name (optional):',
   EMAIL_TO_VALIDATE         => 'E-mail (to validate your registration):',
   PASSWORD                  => 'Password:',
   RETYPE_PASSWORD           => 'Retype Password:',
   CURRENT_EMAIL             => 'Current E-mail:',
   NEW_EMAIL                 => 'New E-mail:',
   RETYPE_NEW_EMAIL          => 'Retype New E-mail:',
   NEW_REALNAME              => 'Your full name:',
   CURRENT_PASSWORD          => 'Current Password:',
   NEW_PASSWORD              => 'New Password:',
   RETYPE_NEW_PASSWORD       => 'Retype New Password:',
   CURRENT_APP_PASSWORD      => 'Current %s Password:',
   CURRENT_APP_USERNAME      => 'Current %s Username:',
   TYPE_PROPER_OPENID        => 'Please type in a proper OpenID.',
   REMEMBER_ME               => 'Remember me',
   SUBMIT                    => 'Submit',
   REGISTER                  => 'Register',
   MY_ACCOUNT                => 'My Account',
   FORGOTTEN_PASSWORD        => 'Forgotten Password?',
   CLOSE                     => '[Close]',
   CANNOT_CONNECT_MAIL       => 'Error: Cannot connect to mail server, an account has not been created.',
   USER_ALREADY_CREATED      => 'Sorry, a user has already been created for the current session.<br><br>Please log in with that account or <br>',
   CREATE_NEW_SESSION        => 'Create a new session.',
   EMAIL_ALREADY_USED        => 'The e-mail provided is already in use by another %s account.',

   MESSAGE_ALREADY_SENT      => 'The e-mail provided has already been used ' .
                                'to create an account, however the account has not been confirmed.<br><br>' .
                                'Please choose one of the following:<br>' .
                                '1. %s<br>' .
                                '2. %s',
   RESEND_CONFIRM_EMAIL      => 'Resend the Confirmation E-mail',
   DELETE_UNCONFIRMED        => 'Delete the Unconfirmed Account',

   CONFIRMATION_EMAIL_SENT   => 'A confirmation e-mail has been sent, please follow the attached link to complete the registration process.',
   ANOTHER_ACCOUNT_IN_USE    => 'Another account is currently in use, please reload the page and log out before attempting to sign in.',
   CANNOT_CONNECT_NOT_SENT   => 'Error: Cannot connect to mail server, your information has not been sent.',
   PROFILE_EMAIL_SENT        => 'A message has been sent to your e-mail address with your profile information.<br><br>Please follow the instructions provided to retrieve your account.',
   CONFIRM_ACCOUNT_PASSWORD  => 'Confirm Account Password',
   ARE_YOU_SURE              => 'Are you sure?',
   WARNING_DELETE_OPENID     => 'Warning: Deleting your %s Account will remove all user information including any saved data or uploaded tracks. Once deleted, you will no longer have access to this %s Account or any of the information associated with it. Are you sure you wish to perform this action?',
   NO                        => 'No',
   YES                       => 'Yes',
   CONFIRM_ACCOUNT_DELETE    => 'Confirm Account Deletion',
   WARNING_IRREVERSIBLE      => 'Warning: This operation is irreversible.',
   NEW_EMAILS_DIFFERENT      => 'New e-mails do not match, please check your spelling.',
   NEW_PASSWORDS_DIFFERENT   => 'New passwords do not match, please check your spelling.',
   INCORRECT_USERNAME        => 'Incorrect username provided, please check your spelling and try again.',
   PLEASE_CONFIRM_INFO       => 'Please confirm your information.',
   EMAIL_CHANGE_SUCCESS      => 'Your e-mail has been changed successfully.',
   PASSWORD_CHANGE_SUCCESS   => 'Your password has been changed successfully.',
   OPENID_ADD_SUCCESS        => 'Your OpenID has been added successfully.',
   OPENID_REMOVE_SUCCESS     => 'Your OpenID has been removed successfully.',
   OPENID_ADD_FAILED         => 'The OpenID could not be added: %s',
   OPERATION_SUCCESS         => 'Operation completed successfully.', 
   BACK                      => 'Back',
   CREATE_ACCOUNT            => 'Create Account',
   OPENID_NOT_ASSOC          => 'The OpenID provided is not associated with any active %s Account. If you would like to create an account now, please confirm or edit the information to set up your account below.',
   SUCCESS                   => 'Success',
   LOADING                   => 'Loading...',
   NO_OPENIDS_ASSOCIATED     => 'There are no OpenIDs currently associated with this %s Account.',
   ADD_ONE                   => 'Add one.',
   ACCOUNT_CREATION_CONF     => 'Account Creation Confirmation',
   THANKS_FOR_CREATING       => 'Thank you for creating an account with %s, %s.' .
                                '<br><br>To complete the account creation process and to log into your %s ' .
                                'account, please type in your username and click the "Continue" button below.',
   MUST_TYPE_USERNAME        => 'You must type in your username to continue.',
   INCORRECT_LINK            => 'The link provided is either incorrect or expired.<br> Please click continue to exit.',
   PENDING                   => 'pending',
   
   WELCOME                   => 'Welcome, %s',
   LOG_OUT_DESC              => 'Click here to log out from %s',
   LOG_OUT                   => 'Log Out',
   CHANGE_SETTINGS_DESC      => 'Click here to change your account settings',
   LOGIN_CREATE_DESC         => 'Click here to log in or create a new account. This will allow you to access your settings and uploaded tracks from multiple computers.',
   LOGIN_REQUEST             => 'Please log in %s',
   LOGIN                     => 'Log in',
   LOGIN_CREATE              => 'Log in / create account',
   LOGIN_REQUIRED            => 'You must log in to access this data source',

   #------------
   # USER TRACKS
   #------------

   UPLOADING                 => 'Uploading...',
   UPLOAD_ERROR              => 'The server returned an error during upload',
   REMOVE_MESSAGE            => '[Remove Message]',
   EDITING_FILE              => 'Editing %s',
   FETCHING                  => 'fetching...',
   CANCELLING                => 'Cancelling',
   NOT_FOUND                 => 'Not Found',
   ADMIN_MODE_WARNING        => 'Admin mode: Uploaded tracks are public',
   SOURCE_FILES              => 'Source files:',
   SHARE_WITH_OTHERS         => 'Share with other users',
   RELOAD_FROM               => '[reload from %s]',
   REMOVE_FROM_MY_SESSION    => 'Remove from my session',
   INTERRUPTED_RESUME        => 'Interrupted [Resume]',
   SHARING                   => 'Sharing:',
   TRACK_IS                  => 'Track is',
   SHARED_WITH_YOU           => '<b>shared</b> with you',
   SHARING_ADD_USER          => 'Add',
   SHARING_PRIVATE           => 'Private',
   SHARING_CASUAL            => 'Casual',
   SHARING_GROUP             => 'Group',
   SHARING_PUBLIC            => 'Public',
   SHARING_HELP              => '<b>Private</b> - Visible only to me.<br>'.
		                        '<b>Casual</b> - Visible to me and anyone I send a link to, but not visible as a public track.<br>'.
		                        '<b>Group</b> - Visible to me and anyone I add to the sharing group. Search for users by typing a portion of their name or email address in the box to a right and click [Add]. An email will be sent to alert them that the track has been shared.<br>'.
		                        '<b>Public</b> - Visible to anyone.',
   UPLOADED_TRACKS_CATEGORY  => 'Custom Tracks:Uploaded Tracks',
   SHARED_WITH_ME_CATEGORY   => 'Custom Tracks:Shared with me',
   SHARE_WITH_THIS_LINK      => 'Share with this link: ',
   USERS                     => 'user(s)',
   USED_BY                   => 'used by',
   PUBLIC_TRACKS             => 'Public Tracks',
   COMMUNITY_TRACKS          => 'Community Tracks',
   THERE_ARE_NO_AVAILABLE_TRACKS => 'There are no available unused %s tracks. Select "Custom Tracks" to see ones you\'ve already added to your session.',
   THERE_ARE_NO_TRACKS_YET   => 'There are no %s tracks yet.',
   NO_PUBLIC_RESULTS         => 'There are no community tracks that match "%s"',
   TOGGLE_DETAILS            => 'Toggle Details',
   SHARED_WITH               => 'shared with',
   NO_ONE                    => 'no one.',
   ENTER_SOMETHING_HERE      => 'Enter a %s here.',
   USERNAME_OR_USER_ID       => 'username or user ID',
   USER_ID                   => 'user ID',
   ADD_BUTTON                => '[Add]',
   EDIT_BUTTON               => '[edit]',
   OVERWRITE                 => 'If this file exists, overwrite it.',
   CHANGING_PERMISSIONS		 => 'Changing sharing permissions...',
   ADDING                    => 'Adding...',
   REMOVING                  => 'Removing...',
   ENTER_KEYWORD             => 'Enter a keyword',
   OR_USER                   => 'or user',
   SHOWING                   => 'showing',
   N_TO_N_OUT_OF             => '%s to %s out of',
   N_FILES                   => '%s files',
   FOUND_N_FILES             => 'Found %s file(s)',
   NEXT_N                    => 'Next %s',
   PREVIOUS_N                => 'Previous %s',
   UPLOADED_BY               => 'uploaded by',
   MATCHING                  => 'matching "<b>%s</b>"',
   PAGE                      => 'page',
   FILTER                    => 'filter',

   #------
   # MISC.
   #------

   HIDE_DETAILS              => 'Hide details',
   SHOW_DETAILS              => 'Show details',
   WORKING                   => 'Working...',

   ZOOM_IN                   => 'Zoom in',
   RECENTER_ON_REGION        => 'Recenter on this region',
   DUMP_AS_FASTA             => 'Dump selection as FASTA',
   ZOOM                      => 'Zoom',

   ABOUT_GBROWSE             => '<p><b>This is the Generic Genome Browser version %s</b></p>' .
                                '<p>It is part of the <a href="http://www.gmod.org">Generic Model Organism (GMOD)</a> ' .
                                'suite of genome analysis software tools.</p>' .
                                '<p>The software is copyright 2002-2010 Cold Spring Harbor Laboratory, ' .
                                'Ontario Institute for Cancer Research, ' .
                                'and the University of California, Berkeley.</p>',
   CHROM_SIZES_UNKNOWN       => 'The chromosome sizes cannot be determined from this data source. Please contact the site administrator for help',
   CHROM_SIZE_FILE_ERROR     => 'An error occurred when opening chromosome sizes file: %s',
   SPECIES                   => 'Species:',
   BUILD                     => 'Build:',
   SPECIES_AND_BUILD_INFO    => 'Species and Build Information',
   MAINTAINED_BY             => 'Maintained by %s',
   CREATED                   => 'Created %s',
   MODIFIED                  => 'Modified %s',
   NO_FURTHER_INFO_AVAILABLE => 'No further information on <b>%s</b> is available.',
   ABOUT_ME_TEXT             => '<h2>User IDs</h2>'.
                                '<p>Your    userID is <b>%s</b></p>'.
                                '<p>Your sessionID is <b>%s</b></p>'.
                                '<p>Your  uploadID is <b>%s</b></p>',
   CLICK_MODIFY_SUBTRACK_SEL => 'Click to modify subtrack selections.',
   CLICK_FOR_MORE            => 'Click for more',
   PLUGIN_BASE_CLASS_DUMP    => "This is the base class for all GBrowse plugins.\n".
                                "The fact that you're seeing this means that the author of ".
                                "this plugin hasn't yet implemented a real dump() method.\n",
   PLUGIN_BASE_CLASS_DESC    => "This is the base class for all GBrowse plugins.\n".
                                "The fact that you're seeing this means that the author of ".
                                "this plugin hasn't yet entered a real description.\n",
   
   CHROM_NOT_FOUND           => 'Configuration error: Chromosome/contig not found!',
   CHROM_NOT_FOUND_DETAILS   => 'Cannot display %s because the chromosome/contig named %s is not defined in the database.',
   NOT_RECOGNIZED_PLUGIN     => '%s is not a recognized plugin',
   NO_PLUGIN_SPECIFIED       => 'No plugin was specified.',

   RULER_TOGGLE_TOOLTIP      => 'Click to enable the ruler. Or, click and drag to reposition.',
   


};
