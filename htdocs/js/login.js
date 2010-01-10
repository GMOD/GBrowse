var LoginScript = '/cgi-bin/gb2/gbrowse_login';
var Logged      = false;
var OpenIDMenu  = false;

var ImgLocation, AppName, AppNameLong;                 // General Information
var CurrentUser, SessionID, LoginPage, EditDetails;    // Dynamic Variables
var UsingOpenID, OpenIDCount, SelectedID;              // OpenID Variables

////////////////////////////////////////////////////////////////////////////////////
//  Logged      = true if the user is logged in, false otherwise.
//  OpenIDMenu  = true if the user is viewing the openID login menu.
//  CurrentUser = holds the value of the currently logged in username.
//  SessionID   = holds the value of the current session id.
//  LoginPage   = holds the value of the current login page name.
//  EditDetails = holds the value of the current account details page name.
//  UsingOpenID = true if the user is logged in with an openID only account.
//  OpenIDCount = holds the number of openIDs associated with a given account.
//  SelectedID  = holds the value of the selected openID which is to be removed.
////////////////////////////////////////////////////////////////////////////////////

//Loads the global variables for the rest of the script
function load_login_globals(images,app,applong) {
    ImgLocation = images;   // eg. /gbrowse2/images/openid
    AppName     = app;      // eg. GBrowse
    AppNameLong = applong;  // eg. The Generic Genome Browser
}

//Formats the entire login popup
function load_login_balloon(event,session,username,openid) {
    SessionID   = session;
    SelectedID  = '';
    LoginPage   = 'main';
    UsingOpenID = openid;

    var html = '<form id=loginMain method=post onSubmit=\'return false;\'>' +

               //Title at top of GBox
               '<div style=border-bottom-style:solid;border-width:1px;padding-left:3px>' +
                 '<b id=loginTitle>Log in</b></div>' +

               '<font face=Arial size=2>' +
               //Table containing login form
               '<table id=loginTable cellspacing=0 cellpadding=3 align=center width=100% style=padding-top:3px>' +
                 //Warning message
                 '<tbody><tr><td id=loginWarning colspan=2 align=center style=display:none;' +
                   'color:red;padding-bottom:3px>All fields are required.</td></tr></tbody>' +

                   //"Edit Details" selection buttons
                 '<tbody>' +
                   '<tr id=loginDSelect style=display:none;><td colspan=2 align=left>' +
                     '<ul style=\'margin:0px 0px 0px 18px\'>' +
                         '<li id=loginChgEmail><a href=#email onClick=edit_details(\'email\')>' +
                             'Change my E-mail</a></li>' +
                         '<li id=loginChgPass><a href=#pass onClick=edit_details(\'password\')>' +
                             'Change my Password</a></li>' +
                         '<li><a href=#add onClick=edit_details(\'openid-add\')>' +
                             'Add OpenID to Account</a></li>' +
                         '<li><a href=#remove onClick=edit_details(\'openid-remove\')>' +
                             'List/Remove OpenIDs</a></li>' +
                         '<li><a href=#delete onClick=edit_details(\'delete\')>' +
                             'Delete My Account</a></li>' +
                   '</ul></td></tr>' +
                 '</tbody>' +

                   //Input text boxes
                 '<tbody id=loginNorm>' +
                   '<tr id=loginURow><td>Username:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);validate_info();} ' +
                       'id=loginUser type=text maxlength=32 style=font-size:9pt size=20></td></tr>' +
                   '<tr id=loginERow style=display:none><td>E-mail (to validate your registration):</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);validate_info();} ' +
                       'id=loginEmail type=text maxlength=64 style=font-size:9pt size=20></td></tr>' +
                   '<tr id=loginPRow><td>Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);validate_info();} ' +
                       'id=loginPass type=password maxlength=32 style=font-size:9pt size=20></td></tr>' +
                   '<tr id=loginP2Row style=display:none><td>Retype Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);validate_info();} ' +
                       'id=loginPass2 type=password maxlength=32 style=font-size:9pt size=20></td></tr>' +
                 '</tbody>' +

                   //"Edit Details" input text boxes
                 '<tbody id=loginDEmail style=display:none;>' +
                   '<tr><td width=40%>Current E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDEOrig type=text maxlength=64 style=font-size:9pt size=18></td></tr>' +
                   '<tr><td width=40%>New E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDENew type=text maxlength=64 style=font-size:9pt size=18></td></tr>' +
                   '<tr><td width=40%>Retype New E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDENew2 type=text maxlength=64 style=font-size:9pt size=18></td></tr>' +
                 '</tbody>' +

                 '<tbody id=loginDPass style=display:none;>' +
                   '<tr><td>Current Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDPOrig type=password maxlength=32 style=font-size:9pt size=18></td></tr>' +
                   '<tr><td>New Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDPNew type=password maxlength=32 style=font-size:9pt size=18></td></tr>' +
                   '<tr><td>Retype New Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDPNew2 type=password maxlength=32 style=font-size:9pt size=18></td></tr>' +
                 '</tbody>' +

                  //Password textbox for adding a new openid to an account
                 '<tbody id=loginDOpenidPass align=center style=display:none;>' +
                   '<tr><td colspan=2>Current '+AppName+' Password:</td></tr>' +
                     '<tr><td colspan=2 style=padding-bottom:6px;><input onKeyPress=if(event.keyCode==13){' +
                       'login_loading(true);edit_details_verify();} id=loginDOPass type=password maxlength=32 ' +
                       'style=font-size:9pt size=24></td></tr>' +
                 '</tbody>' +
                  //Username textbox for adding a new openid to an openid only account
                 '<tbody id=loginDOpenidUser align=center style=display:none;>' +
                   '<tr><td colspan=2>Current '+AppName+' Username:</td></tr>' +
                     '<tr><td colspan=2 style=padding-bottom:6px;><input onKeyPress=if(event.keyCode==13){' +
                       'login_loading(true);edit_details_verify();} id=loginDOUser type=text maxlength=32 ' +
                       'style=font-size:9pt size=24></td></tr>' +
                 '</tbody>' +

                  //OpenID textbox and images
                 '<tbody id=loginDOpenid align=center style=display:none;>' +
                   '<tr><td colspan=2 style=padding-top:6px;>' +
                     '<input onKeyPress=if(event.keyCode==13){login_loading(true);if(LoginPage==\'details\'){' +
                       'edit_details_verify();}else{validate_info();}} value=http:// ' +
                       'id=loginDONew type=text maxlength=128 size=26 style=font-size:9pt;' +
                       'padding-left:16px;background-image:url('+ImgLocation+'/openid-logo.gif);' +
                       'background-repeat:no-repeat;border:solid;></td></tr>' +
                   '<tr><td colspan=2>' +
                       '<image onClick=login_openid_html(\'http://openid.aol.com/screenname\',22,10); ' +
                         'src='+ImgLocation+'/aim-logo.png alt=\'AIM\' height=20px width=20px>' +
                       '<image onClick=login_openid_html(\'http://blogname.blogspot.com/\',7,8); ' +
                         'src='+ImgLocation+'/blogspot-logo.png alt=\'Blogspot\' height=20px width=20px>' +
                       '<image onClick=login_openid_html(\'http://username.livejournal.com/\',7,8); ' +
                         'src='+ImgLocation+'/livejournal-logo.png alt=\'LiveJournal\' height=20px width=20px>' +
                       '<image onClick=login_openid_html(\'http://username.myopenid.com/\',7,8); ' +
                         'src='+ImgLocation+'/myopenid-logo.png alt=\'myOpenID\' height=20px width=20px>' +
                       '<image onClick=login_openid_html(\'https://me.yahoo.com/username\',21,8); ' +
                         'src='+ImgLocation+'/yahoo-logo.png alt=\'YAHOO\' height=20px width=20px>' +
                   '</td></tr>' +
                 '</tbody>' +

                  //Initially empty section used for populating with a list of openids associated with an account
                 '<tbody id=loginDList style=display:none;></tbody>' +

                  //Submit, remember me and cancel buttons
                 '<tbody>' +
                   '<tr><td id=loginButtons colspan=2 align=center style=padding-bottom:3px;padding-top:6px>' +
                     '<input id=loginSubmit style=font-size:90% type=button value=\'Log in\'' +
                       'onClick=login_loading(true);$(\'loginWarning\').hide();validate_info(); />' +
                     '<b id=loginBreak>&nbsp; &nbsp;</b>' +
                     '<input id=loginRemember type=checkbox checked>' +
                       '<font id=loginRememberTxt>Remember me</font></input>' +
                     '<input id=loginCancel style=font-size:90%;display:none type=button value=\'Cancel\'' +
                       'onClick=login_page_change(\'main\') /></td></tr>' +

                   '<tr><td id=loginSpacing colspan=2 style=display:none><br></td></tr>' +

                    //"Edit Details" submit and cancel buttons
                   '<tr><td id=loginDButtons colspan=2 align=center style=display:none;' +
                     'padding-bottom:3px;padding-top:3px>' +
                     '<input id=loginDSubmit2 style=font-size:90% type=button value=\'Remove\'' +
                       'onClick=edit_details(\'openid-remove-verify\'); />' +
                     '<input id=loginDSubmit style=font-size:90% type=button value=\'Submit\'' +
                       'onClick=login_loading(true);$(\'loginWarning\').hide();edit_details_verify(); />' +
                     '&nbsp; &nbsp;' +
                     '<input id=loginDCancel style=font-size:90% type=button value=\'Cancel\'' +
                       'onClick=edit_details(\'home\') /></td></tr>' +

                    //Register, My Account and Forgotten Password selections
                   '<tr id=loginOpts align=center><td id=loginOptsContent1 colspan=2><font size=1>' +
                     '<a href=#register onClick=login_page_change(\'create\');>Register</a> / ' +
                     '<a href=#account onClick=login_page_change(\'edit\');>My Account</a> / ' +
                     '<a href=#forgot onClick=login_page_change(\'forgot\');>Forgotten Password?</a>' +
                   '</font></td>' +
                   '<td id=loginOptsContent2 colspan=2 style=display:none;><font size=1>' +
                     'Register / My Account / Forgotten Password?</font></td>' +
                   '</tr>' +
                 '</tbody>' +

                  //Switch between regular and openid login pages
                 '<tbody id=loginOpenID>' +
                   '<tr><td id=loginOpenIDY colspan=2 align=center style=padding-top:12px>' +
                     'Have an OpenID? <a href=#openid onClick=login_page_openid(true)>' +
                       'Sign in</a>.</td></tr>' +
                   '<tr><td id=loginOpenIDN colspan=2 align=center style=display:none;padding-top:12px>' +
                     'Don\'t have an OpenID? <a href=#noopenid onClick=login_page_openid(false)>' +
                       'Go Back</a>.</td></tr>' +
                 '</tbody>' +
               '</table></font>'+
	       '<img id="loginBusy" src="/gbrowse2/images/spinner.gif" style="display:none;float:left" />' +
	       '&nbsp;<a style="float:right;font-size:90%" href="javascript:void(0)" '+
	                'onClick="Balloon.prototype.hideTooltip(1)">[Close]</a>' +
	       '</form>';

    GBox.showTooltip(event,html,1,320);
    $('loginMain').style.width = '268px';

    //If the user is logged in, display only the "edit account details" page when login is called
    if(username != false) {
        Logged = true;
        CurrentUser = username;
        login_page_change('edit');
        edit_details('home');
    } else {
        CurrentUser = '';
    }

    //Format the login popup accordingly if it is opened with the openid login screen
    if(OpenIDMenu) {login_page_openid(true);}
    return;
}

//Shows, hides, and changes the titles of elements for a given page in the login popup
function login_page_change(page) {
    LoginPage = page;
    login_loading(false);
    $('loginPass').value = '';
    $('loginPass2').value = '';
    $('loginWarning').hide(); $('loginOpenID').hide();

    switch(page) {
    case 'main':
        $('loginWarning').style.color = 'red';
        $('loginTitle').innerHTML     = 'Log in';
        $('loginSubmit').value        = 'Log in';
        $('loginCancel').value        = 'Cancel';
        $('loginOpenID').blur();
        $('loginOpts').blur();
        $('loginOpenID').show();
        $('loginERow').hide();  $('loginSubmit').show();
        $('loginP2Row').hide(); $('loginDSelect').hide();
        break;
    case 'create':
        $('loginTitle').innerHTML = 'Register';
        $('loginSubmit').value    = 'Register';
        $('loginERow').show();
        $('loginP2Row').show();
        break;
    case 'forgot':
        $('loginTitle').innerHTML = 'Forgot my password';
        $('loginSubmit').value    = 'E-mail my password';
        $('loginERow').show();
        break;
    case 'edit':
        $('loginTitle').innerHTML = 'Edit account details';
        $('loginSubmit').value    = 'Continue';
        $('loginOpenID').show();
        break;
    default:
        return;
    }

    if(page == 'main') {
        $('loginOpts').show();   $('loginRemember').show();
        $('loginCancel').hide(); $('loginRememberTxt').show();
    } else {
        $('loginOpts').hide();   $('loginRemember').hide();
        $('loginCancel').show(); $('loginRememberTxt').hide();
    }

    if(page =='forgot') {
        $('loginBreak').hide(); $('loginURow').hide(); $('loginPRow').hide();
    } else {
        $('loginBreak').show(); $('loginURow').show(); $('loginPRow').show();
    }

    if(page == 'forgot') {
        $('loginTable').style.paddingTop = '18px';
        $('loginButtons').style.paddingTop = '18px';
    } else if(page == 'edit') {
        $('loginTable').style.paddingTop = '12px';
        $('loginButtons').style.paddingTop = '12px';
    } else {
        $('loginTable').style.paddingTop = '3px';
        $('loginButtons').style.paddingTop = '3px';
    }

    if(OpenIDMenu && ((page == 'main') || (page == 'edit'))) {
        $('loginDOpenid').show(); $('loginNorm').hide(); $('loginDONew').focus(); 
    } else {
        $('loginDOpenid').hide(); $('loginNorm').show();
        if(page == 'forgot') {$('loginEmail').focus();}
        else {$('loginUser').focus();}
    }

    return;
}

//Switches between a normal username/pass form and an openid form
function login_page_openid(openID) {
    $('loginWarning').hide();
    if(openID) {
        OpenIDMenu = true;
        $('loginOpenIDY').hide();  $('loginDOpenid').show();
        $('loginOpenIDN').show();  $('loginNorm').hide();
        $('loginDONew').focus();
    } else {
        OpenIDMenu = false;
        $('loginOpenIDY').show();  $('loginDOpenid').hide();
        $('loginOpenIDN').hide();  $('loginNorm').show();
        $('loginUser').focus();
    }
}

//Used to disable everything while AJAX requests are being processed
function login_loading(toggle) {
    if(toggle) {
        $('loginSubmit').disabled  = true;   $('loginCancel').disabled  = true;
        $('loginDSubmit').disabled = true;   $('loginDCancel').disabled = true;
        $('loginOptsContent1').hide();       $('loginOptsContent2').show();

        $('loginOpenIDY').innerHTML = 'Have an OpenID? Sign in.';
        $('loginOpenIDN').innerHTML = 'Don\'t have an OpenID? Go Back.';
    } else {
        $('loginSubmit').disabled  = false;  $('loginCancel').disabled  = false;
        $('loginDSubmit').disabled = false;  $('loginDCancel').disabled = false;
        $('loginOptsContent1').show();       $('loginOptsContent2').hide();

        $('loginOpenIDY').innerHTML = 'Have an OpenID? <a href=#openid onClick=' +
                                      'login_page_openid(true)>Sign in</a>.';
        $('loginOpenIDN').innerHTML = 'Don\'t have an OpenID? <a href=#noopenid onClick=' +
                                      'login_page_openid(false)>Go Back</a>.';
    }
}

//Checks to make sure that all the information required by a given page is there when "Submit" is clicked
function validate_info() {
    var user   = $('loginUser').getValue().length;
    var email  = $('loginEmail').getValue().length;
    var pass   = $('loginPass').getValue();
    var pass2  = $('loginPass2').getValue();
    var openid = $('loginDONew').getValue();
    var html   = '<' + String($('loginWarning').innerHTML).split('<')[2] + '</font>';

    switch(LoginPage) {
    case 'create':
        if(user==0 || email==0 || pass.length==0 || pass2.length==0) {
            $('loginWarning').innerHTML = 'All fields are required.';
        } else if(pass != pass2) {
            $('loginWarning').innerHTML = 'Passwords do not match.';
        } else {
            add_user();
            return;
        }
        break;
    case 'forgot':
        if(email==0) {$('loginWarning').innerHTML = 'All fields are required.';}
        else {email_user_info();return;}
        break;
    case 'new-openid':
        if(user==0) {
            $('loginWarning').innerHTML = 'All fields are required.<br>'+html;
        } else {
            add_openid_user(CurrentUser,html);
            return;
        }
        break;
    default:
        if(OpenIDMenu) {
            if(openid.length==0 || openid=='http://' || openid=='https://' || openid.indexOf('.')==-1) {
                $('loginWarning').innerHTML = 'Please type in a proper OpenID.';
            } else {
                check_openid(openid);
                return;
            }
        } else {
            if(user==0 || pass.length==0) {$('loginWarning').innerHTML = 'All fields are required.';}
            else {login_validation();return;}
        }
        break;
    }

    $('loginWarning').show();
    login_loading(false);
    return;
}


//******************************************************************
// Create New User Functions:
//******************************************************************

//Adds the user to the database (regular login)
function add_user() {
    var username = $('loginUser').getValue();
    var password = $('loginPass').getValue();
    var email    = $('loginEmail').getValue();
    $('loginBusy').show();

    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['add_user_check'],
                      user:     username,
                      email:    email,
                      pass:     password,
                      session:  SessionID
                     },
        onSuccess: function (transport) {
	    $('loginBusy').hide();
            var results = transport.responseText;

            if(results == '') {
                $('loginWarning').innerHTML = 'Error: Cannot connect to mail ' +
                    'server, an account has not been created.';
            }

            if(results=='Session Error' || results == 'E-mail in use' || results=='Message Already Sent') {
                login_loading(false);
                $('loginCancel').value = 'Back';

                if(results == 'Session Error') {
                    $('loginWarning').innerHTML = 'Sorry, a user has already been created ' +
                        'for the current session.<br><br>Please log in with that account or<br>' +
                        '<a href=#reset onClick="$(\'balloon\').hide();$(\'closeButton\').hide();' +
                            'login_get_account(\'Reset\',\'Reset\',0,false);return false;">' +
                        'click here</a> to create a new session.';
                } else if(results == 'E-mail in use') {
                    $('loginWarning').innerHTML = 'The e-mail provided is already in use by ' +
                        'another '+AppName+' account. If you have forgotten your password and wish ' +
                        'to recover your account, <a href=#forgot onClick="login_page_change(\'main\');' +
                            'login_page_change(\'forgot\');login_loading(true);' +
                            'email_user_info();return false;">click here</a>.';
                } else if(results == 'Message Already Sent') {
                    $('loginWarning').innerHTML = 'The e-mail provided has already been used ' +
                        'to create an account, however the account has not been confirmed.<br><br>' +
                        'Please choose one of the following:<br>' +
                        '1. <a href=#resend onClick="edit_confirmation(1);return false;">' +
                            'Resend the Confirmation E-mail</a><br>' +
                        '2. <a href=#remove  onClick="edit_confirmation(0);return false;">' +
                            'Delete the Unconfirmed Account</a>';
                }

                $('loginURow').hide(); $('loginBreak').hide();
                $('loginPRow').hide(); $('loginSubmit').hide();
                $('loginERow').hide(); $('loginWarning').show();
                $('loginP2Row').hide();
            } else {
                $('loginWarning').innerHTML = results;
                UsingOpenID = false;
                login_user(username);
            }
        }
    });
    return;
}

//Resends or simply deletes an existing unconfirmed account if the same e-mail is used for a new account
function edit_confirmation(resend) {
    $('loginWarning').innerHTML = '';
    login_page_change('main');
    login_page_change('create');
    login_loading(true);

    var email = $('loginEmail').getValue();
    $('loginBusy').show();
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['edit_confirmation'],
                      email:  email,
                      option: resend
                     },
        onSuccess: function (transport) {
	    $('loginBusy').hide();
            $('loginWarning').innerHTML = transport.responseText;
            login_user(email);
        }
    });
    return;
}

//Adds the user to the database if they didn't previousily exist (openid login)
function add_openid_user(openid,html) {
    var username = $('loginUser').getValue();
    var remember;

    $('loginWarning').hide();
    if($('loginRemember').checked) {remember=1;}
    else {remember=0;}
    $('loginBusy').show();

    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['add_openid_user'],
                      user:     username,
                      openid:   openid,
                      session:  SessionID,
                      remember: remember
                     },
        onSuccess: function (transport) {
            var results = transport.responseText;
	    $('loginBusy').hide();
            if(results == 'Session Error') {
                login_loading(false);
                $('loginCancel').value      = 'Back';
                $('loginWarning').innerHTML = 'Sorry, a user has already been created ' +
                    'for the current session.<br><br>Please log in with that account or<br>' +
                    '<a href=#reset onClick="$(\'balloon\').hide();$(\'closeButton\').hide();' +
                        'login_get_account(\'Reset\',\'Reset\',0,false);return false;">' +
                    'click here</a> to create a new session.';

                $('loginURow').hide();  $('loginSubmit').hide();
                $('loginBreak').hide(); $('loginWarning').show();
            } else {
                if(results != 'Success') {
                    $('loginWarning').innerHTML = results + '<br>' + html;
                } else {
                    $('loginWarning').innerHTML = results;
                    LoginPage = 'main';
                    UsingOpenID = true;
                }
                login_user(username,SessionID,remember);
            }
        }
    });
    return;
}


//******************************************************************
// Log In Validation Functions:
//******************************************************************

//Checks to make sure that the provided credentials are valid
function login_validation() {
    var username = $('loginUser').getValue();
    var password = $('loginPass').getValue();
    var session  = '';
    var remember;

    if(LoginPage=='edit') {remember=2;}
    else {
        if($('loginRemember').checked) {remember=1;}
        else {remember=0;}
    }

    $('loginBusy').show();
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['validate'],
                      user:     username,
                      pass:     password,
                      remember: remember
                     },
        onSuccess: function (transport) {
	    $('loginBusy').hide();
            var results = transport.responseText;
            if(results.indexOf('session')!=-1) {
                session = results.slice(7);
                $('loginWarning').innerHTML = 'Success';
            } else {
                $('loginWarning').innerHTML = results;
            }
            UsingOpenID = false;
            login_user(username,session,remember);
        }
    });
    return;
}

//Logs in the user or sends them to the proper screen when credentials are provided
function login_user(username,session,remember) {
    if ($('loginWarning').innerHTML != 'Success') {
        $('loginWarning').show();
        login_loading(false);
        return;
    } else {
        switch(LoginPage) {
        case 'edit':
            CurrentUser = username;
            edit_details('home');
            return;
        case 'create':
            $('loginCancel').value        = 'Back';
            $('loginWarning').style.color = 'blue';
            $('loginWarning').innerHTML   = 'A confirmation e-mail has been sent, please ' +
                'follow the attached link to complete the registration process.';

            $('loginURow').hide(); $('loginERow').hide();  $('loginBreak').hide();
            $('loginPRow').hide(); $('loginP2Row').hide(); $('loginSubmit').hide();
            login_loading(false);
            $('loginWarning').show();
            return;
        case 'main':
            login_get_account(username,session,remember,false)
            return;
        default:
            return;
        }
    }
}

//Refresh the page with the user logged in
function login_get_account(username,session,remember,openid) {
    if ($('loginBusy') != null) $('loginBusy').show();
    new Ajax.Request(document.URL,{
        method:      'post',
        parameters: {action:   'authorize_login',
                     username: username,
                     session:  session,
                     remember: remember,
                     openid:   UsingOpenID
                    },
        onSuccess: function(transport) {
	    if ($('loginBusy') != null) $('loginBusy').hide();
            var results = transport.responseJSON;
            if(results.id != null) {
                if(results.id == 'error') {
                    if(openid) {
                        var command = 'load_login_balloon(new fakeEvent(),"'+session+'",false,false);' +
                                      'login_blackout(false,"");login_get_account_error();';
                        setTimeout(command,2000);
                    } else {
                        login_get_account_error();
                    }
                } else {
                    login_load_account(String(location.href).split('?')[0],results);
                }
            }
        }
    });
    return;
}

//Display this message if an error occurs when attempting to retrieve a user's session
function login_get_account_error() {
    login_page_change('main');
    UsingOpenID = false;
    $('loginWarning').innerHTML = 'Another account is currently in use, ' +
        'please reload the page and log out before attempting to sign in.';
    $('loginWarning').show();
    login_loading(false);
    return;
}

//Load the user's account
function login_load_account(to,p) {
    var myForm = document.createElement('form');
        myForm.method = 'post';
        myForm.action = to;

    for (var k in p) {
        var myInput = document.createElement('input');
            myInput.setAttribute('name', k);
            myInput.setAttribute('value', p[k]);
            myInput.style.display = 'none';
            myForm.appendChild(myInput);
    }

    document.body.appendChild(myForm);
    myForm.submit();
    document.body.removeChild(myForm);
    return;
}


//******************************************************************
// Forgot Password Function:
//******************************************************************

//E-mails the user their account information
function email_user_info() {
    var email = $('loginEmail').getValue();
    $('loginBusy').show();

    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['email_info'],
                      email: email
                     },
        onSuccess: function (transport) {
	    $('loginBusy').hide();
            var result = transport.responseText;
            if(result != 'Success') {
                if(result == '') {
                    $('loginWarning').innerHTML = 'Error: Cannot connect to mail ' +
                        'server, your information has not been sent.';
                } else {
                    $('loginWarning').innerHTML = result;
                }
                $('loginWarning').show();
            } else {
                $('loginCancel').value        = 'Back';
                $('loginWarning').style.color = 'blue';
                $('loginWarning').innerHTML = 'A message has been sent to your' +
                    ' e-mail address with your profile information.<br><br>' +
                    'Please follow the instructions provided to retrieve' +
                    ' your account.';

                $('loginERow').hide();  $('loginSubmit').hide();
                $('loginBreak').hide(); $('loginWarning').show();
            }
            login_loading(false);
        }
    });
    return;
}


//******************************************************************
// Change Account E-mail/Password Functions:
//******************************************************************

//Shows, hides, and changes the titles of elements for a given page in the account details menu
function edit_details(details) {
    LoginPage = 'details';
    $('loginWarning').hide();

    if(details == 'home') {
        $('loginMain').reset();
        $('loginTitle').innerHTML = 'Edit account details';
        $('loginCancel').value    = 'Go Back';
        $('loginTable').style.paddingTop = '18px';
        login_loading(false);

        $('loginDSelect').show(); $('loginDOpenidPass').hide();
        $('loginSubmit').hide();  $('loginDOpenidUser').hide();
        $('loginOpenID').hide();  $('loginDButtons').hide();
        $('loginDPass').hide();   $('loginDOpenid').hide();
        $('loginDList').hide();   $('loginDEmail').hide();
        $('loginNorm').hide();    $('loginBreak').hide();

        if(UsingOpenID) {$('loginChgEmail').hide(); $('loginChgPass').hide();}
        else {$('loginChgEmail').show(); $('loginChgPass').show();}

        if(Logged == false) {$('loginButtons').show(); $('loginSpacing').hide();}
        else {$('loginButtons').hide(); $('loginSpacing').show();}
        return;
    } else {
        $('loginTable').style.paddingTop = '3px';
        $('loginWarning').style.color    = 'red';
        $('loginDCancel').value          = 'Cancel';
        $('loginDSubmit').value          = 'Submit';
        login_loading(false);

        $('loginDSelect').hide();  $('loginButtons').hide();
        $('loginDButtons').show(); $('loginSpacing').hide();
        $('loginDSubmit2').hide(); $('loginDSubmit').show();  
    }  

    switch(details) {
    case 'email':
        $('loginTitle').innerHTML = 'Change my E-mail';
        $('loginDEmail').show();
        $('loginDEOrig').focus();
        EditDetails = 'email';
        return;
    case 'password':
        $('loginTitle').innerHTML = 'Change my Password';
        $('loginDPass').show();
        $('loginDPOrig').focus();
        EditDetails = 'password';
        return;
    case 'openid-add':
        $('loginTitle').innerHTML = 'Add OpenID to Account';
        EditDetails = 'openid-add';
        $('loginDOpenid').show();
        if(UsingOpenID) {$('loginDOpenidUser').show(); $('loginDOUser').focus();}
        else {$('loginDOpenidPass').show(); $('loginDOPass').focus();}
        return;
    case 'openid-remove':
        $('loginDList').innerHTML   = '<tr><td></td></tr>';
        $('loginTitle').innerHTML   = 'Remove OpenID from Account';
        $('loginDSubmit2').disabled = true;
        $('loginDList').show();
        $('loginDSubmit').hide();
        $('loginDSubmit2').show();
        EditDetails = 'openid-remove';
        list_openid();
        return;
    case 'openid-remove-verify':
        if(UsingOpenID && OpenIDCount == 1) {
            $('loginWarning').innerHTML = 'Sorry, but you need at least one active ' +
                'OpenID associated with this account in order to access '+AppName+'.';
            $('loginWarning').show();
            $('loginDSubmit').hide();
            $('loginDSubmit2').show();
            $('loginDSubmit2').disabled = true;
        } else {
            $('loginTitle').innerHTML = 'Confirm Account Password';
            $('loginDList').hide();
            if(UsingOpenID) {$('loginDOpenidUser').show(); $('loginDOUser').focus();}
            else {$('loginDOpenidPass').show(); $('loginDOPass').focus();}
        }
        return;
    case 'delete':
        $('loginTitle').innerHTML   = 'Are You Sure?';
        $('loginWarning').innerHTML = 'Warning: Deleting your '+AppName+' Account will remove all user ' +
            'information including any saved data or uploaded tracks. Once deleted, you will no longer ' +
            'have access to this '+AppName+' Account or any of the information associated with it. ' +
            'Are you sure you wish to perform this action?';
        $('loginWarning').show();
        $('loginDCancel').value = 'No';
        $('loginDSubmit').value = 'Yes';
        EditDetails = 'delete';
        return;
    case 'delete-confirm':
        $('loginTitle').innerHTML   = 'Confirm Account Deletion';
        $('loginWarning').innerHTML = 'Warning: This operation is irreversible.';
        $('loginWarning').show();
        if(UsingOpenID) {$('loginDOpenidUser').show(); $('loginDOUser').focus();}
        else {$('loginDOpenidPass').show(); $('loginDOPass').focus();}
        EditDetails = 'delete-confirm';
        return;
    default:
        return;
    }
}

//Checks to make sure that all the information required by a
//given page is there when "Submit" is clicked in account details
function edit_details_verify() {
    var old_email  = $('loginDEOrig').getValue();
    var new_email  = $('loginDENew').getValue();
    var new_email2 = $('loginDENew2').getValue();

    var old_pass  = $('loginDPOrig').getValue();
    var new_pass  = $('loginDPNew').getValue();
    var new_pass2 = $('loginDPNew2').getValue();

    var openid = $('loginDONew').getValue();
    var ouser  = $('loginDOUser').getValue();
    var opass  = $('loginDOPass').getValue();

    switch(EditDetails) {
    case 'email':
        if(old_email.length==0 || new_email.length==0 || new_email2.length==0) {
            $('loginWarning').innerHTML = 'All fields are required.';
        } else if(new_email != new_email2) {
            $('loginWarning').innerHTML = 'New e-mails do not match, please check your spelling.';
        } else {
            edit_details_submit(CurrentUser,'email',old_email,new_email);
            return;
        }
        break;
    case 'password':
        if(old_pass.length==0  || new_pass.length==0  || new_pass2.length==0) {
            $('loginWarning').innerHTML = 'All fields are required.';
        } else if(new_pass != new_pass2) {
            $('loginWarning').innerHTML = 'New passwords do not match, please check your spelling.';
        } else {
            edit_details_submit(CurrentUser,'pass',old_pass,new_pass);
            return;
        }
        break;
    case 'openid-add':
        if(openid.length==0 || (!UsingOpenID && opass.length==0) || (UsingOpenID && ouser.length==0)) {
            $('loginWarning').innerHTML = 'All fields are required.';
        } else if(UsingOpenID && CurrentUser != ouser) {
            $('loginWarning').innerHTML = 'Incorrect username provided, please check your spelling and try again.';
        } else {
            change_openid(CurrentUser,opass,openid,'add');
            return;
        }
        break;
    case 'openid-remove':
        if((!UsingOpenID && opass.length==0) || (UsingOpenID && ouser.length==0)) {
            $('loginWarning').innerHTML = 'Please confirm your information.';
        } else if(UsingOpenID && CurrentUser != ouser) {
            $('loginWarning').innerHTML = 'Incorrect username provided, please check your spelling and try again.';
        } else {
            change_openid(CurrentUser,opass,SelectedID,'remove');
            return;
        }
        break;
    case 'delete':
        edit_details('delete-confirm');
        return;
    case 'delete-confirm':
        if((!UsingOpenID && opass.length==0) || (UsingOpenID && ouser.length==0)) {
            $('loginWarning').innerHTML = 'Please confirm your information.';
        } else if(UsingOpenID && CurrentUser != ouser) {
            $('loginWarning').innerHTML = 'Incorrect username provided, please check your spelling and try again.';
        } else {
            login_delete_user(CurrentUser,opass);
            return;
        }
        break;
    default:
        return;
    }

    $('loginWarning').show();
    login_loading(false);
    return;
}

//Updates either the user's e-mail or password
function edit_details_submit(username,column,old_val,new_val) {  
    $('loginBusy').show();
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['edit_details'],
                      user:    username,
                      column:  column,
                      old_val: old_val,
                      new_val: new_val
                     },
        onSuccess: function (transport) {
	    $('loginBusy').hide();
            $('loginWarning').innerHTML = transport.responseText;
            edit_details_confirm();
        }
    });
    return;
}

//Confirms or reports any errors from actions taken in account details
function edit_details_confirm() {
    if ($('loginWarning').innerHTML != 'Success') {
        $('loginWarning').show();
        login_loading(false);
    } else {
        $('loginWarning').style.color = 'blue';
        switch(EditDetails) {
            case 'email': $('loginWarning').innerHTML = 'Your e-mail has been changed successfully.';break;
            case 'password': $('loginWarning').innerHTML = 'Your password has been changed successfully.';break;
            case 'openid-add': $('loginWarning').innerHTML = 'Your OpenID has been added successfully.';break;
            case 'openid-remove': $('loginWarning').innerHTML = 'Your OpenID has been removed successfully.';break;
            default: $('loginWarning').innerHTML = 'Operation completed successfully.';break;
        }
        edit_details('home');
        $('loginWarning').show();
    }
    return;
}


//******************************************************************
// OpenID Functions:
//******************************************************************

//Switches the openid text based on the icon selected
function login_openid_html(html,start,strLength) {
    $('loginDONew').value = html;
    $('loginDONew').focus();
    $('loginDONew').setSelectionRange(start, start + strLength);
    return;
}

//Send the user to their openid provider to be authenticated
function check_openid(openid) {
    $('loginBusy').show();
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['check_openid'],
                      openid:  openid,
                      session: SessionID,
                      option:  LoginPage
        },
        onSuccess: function (transport) {
	    $('loginBusy').hide();
            var results = transport.responseText;
            if(results.indexOf('Location:')!=-1) {
                document.location.href = results.slice(10);
            } else {
                $('loginWarning').innerHTML = results;
                $('loginWarning').show();
                login_loading(false);
            }
        }
    });
    return;
}

//Process the GET variables for the openid authentication
function process_openid() {
    var i, element;
    var hash = new Array();
    var args = String(String(document.location).split('#')[0]).split('&');

    for(i=1; i<args.length; i++) {
        element = String(args[i]).split('=');
        hash[2*(i-1)] = element[0];             //element
        hash[(2*i)-1] = unescape(element[1]);   //value
    }

    return hash;
}

//Simulate an event handler for use with calling Balloon.js in the onLoad event
function fakeEvent() {
    var clientX = 10;
    if (parseInt(navigator.appVersion) > 3) {
        if(navigator.appName=='Netscape') {
            clientX = window.innerWidth - 30;
        } else if(navigator.appName.indexOf('Microsoft')!=-1) {
            clientX = document.body.offsetWidth - 30;
        }
    }

    this.srcElement     = new fakeTarget();   //The element that fired the event
    this.target         = new fakeTarget();   //Also the element that fired the event
    this.type           = 'mousedown';        //Type of event
    //this.returnValue  (undefined)           //Determines whether the event is cancelled
    this.cancelBubble   = true;               //Can cancel an event bubble
    this.clientX        = clientX;            //Mouse pointer X coordinate relative to window
    this.clientY        = 5;                  //Mouse pointer Y coordinate relative to window
    //this.offsetX      (undefined)           //Mouse pointer X coordinate relative to element that fired the event
    //this.offsetY      (undefined)           //Mouse pointer Y coordinate relative to element that fired the event
    this.button         = 0;                  //Any mouse buttons that are pressed
    this.altKey         = false;              //True if the alt key was also pressed
    this.ctrlKey        = false;              //True if the ctrl key was also pressed
    this.shiftKey       = false;              //True if the shift key was also pressed
    //this.keyCode      (undefined)           //Returns UniCode value of key pressed
}

//Part of fakeEvent()
function fakeTarget() {
    this.nodeType = 4;
}

//Work around which removes the openid return cookie, otherwise it keeps popping up
function remove_openid_cookie() {
    var currentUrl  = String(String(document.location).split('#')[0]).split('?')[0];
        currentUrl  = String(currentUrl).split('http://')[1];
        currentUrl  = currentUrl.slice(currentUrl.indexOf('/'));
    document.cookie = 'gbrowse_sess=; max-age=0; path='+currentUrl;
}

//Retrieve the GET variables and pass them to the OpenID handler
function confirm_openid(session,page,logged_in) {
    remove_openid_cookie();
    var callback = process_openid();
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['confirm_openid'],
                      callback: callback,
                      session:  session,
                      option:   page
        },
        onSuccess: function (transport) {
            var results = transport.responseJSON;
            if(page == 'edit' || page == 'openid-add') {
                var command = 'confirm_openid_error("'+session+'","'+page+'",'+logged_in+',' +
                              '"'+results[0].error+'","'+results[0].user+'","'+results[0].only+'")';
                setTimeout(command,2000);
            } else if(results[0].error != null) {
                var command = 'confirm_openid_error("'+session+'","'+page+'",'+logged_in+',' +
                              '"'+results[0].error+'","'+results[0].openid+'")';
                setTimeout(command,2000);
            } else {
                if(results[0].only == 0) {UsingOpenID = false;}
                else {UsingOpenID = true;}
                login_get_account(results[0].user,results[0].session,results[0].remember,true);
            }
        }
    });
    return;
}

//Handle the different cases and error messages associated with openid accounts
function confirm_openid_error(session,page,logged_in,error,openid,only) {
    var event  = new fakeEvent();
    (only == 0 || logged_in) ? OpenIDMenu = false : OpenIDMenu = true;
    load_login_balloon(event,session,false,false);
    login_blackout(false,'');

    if(only == 1) {UsingOpenID=true;}
    if(page == 'openid-add') {login_page_change('edit');}
    else {login_page_change(page);}

    if(error.indexOf('has not been used before.')!=-1 && LoginPage=='main') {
        LoginPage                     = 'new-openid';
        CurrentUser                   = openid;
        $('loginCancel').value        = 'Back';
        $('loginSubmit').value        = 'Create Account';
        $('loginWarning').innerHTML   = '<font /><font color=blue>The OpenID provided is not ' +
            'associated with any active '+AppName+' Account. If you would like to create an ' +
            'account now, please type a username to identify yourself below.</font>';

        $('loginRemember').hide();  $('loginRememberTxt').hide();
        $('loginWarning').show();   $('loginDOpenid').hide();
        $('loginOpenID').hide();    $('loginNorm').show();
        $('loginCancel').show();    $('loginPRow').hide();
        $('loginOpts').hide();      $('loginUser').focus();
    } else if(error == 'error') {
        $('loginWarning').innerHTML = 'Another account is currently in use, ' +
            'please refresh the page and log out before attempting to sign in.';
        $('loginWarning').show();
    } else if(page == 'edit') {
        $('loginWarning').innerHTML = error;
        if($('loginWarning').innerHTML == 'undefined') {$('loginWarning').innerHTML = 'Success';}
        LoginPage = page;
        login_user(openid);
    } else if(page == 'openid-add') {
        $('loginWarning').innerHTML = openid;
        if($('loginWarning').innerHTML == 'undefined') {
            $('loginWarning').innerHTML = error;
            $('loginWarning').show();
        } else {
            $('loginWarning').innerHTML = error;
            Logged = logged_in;
            CurrentUser = openid;
            edit_details('home');
            edit_details('openid-add');
            edit_details_confirm();
        }
    } else {
        $('loginWarning').innerHTML = error;
        $('loginWarning').show();
    }

    login_loading(false);
    return;
}

//Adds or Removes an openid from an account
function change_openid(user,pass,openid,option) {
    $('loginBusy').show();
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['change_openid'],
                      user:   user,
                      pass:   pass,
                      openid: openid,
                      option: option
        },
        onSuccess: function (transport) {
	    $('loginBusy').hide();
            var results = transport.responseText;
            if(results.indexOf('Location:')!=-1) {
                document.location.href = results.slice(10);
            } else {
                $('loginWarning').innerHTML = results;
                edit_details_confirm();
            }
        }
    });
    return;
}

//Gets the list of all openids associated with an account
function list_openid() {
    $('loginWarning').innerHTML = 'Loading...';
    $('loginWarning').show();
    $('loginBusy').show();
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['list_openid'],
                      user:   CurrentUser
        },
        onSuccess: function (transport) {
	    $('loginBusy').hide();
            var results = transport.responseJSON;
            if(results[0].error != null) {
                $('loginWarning').innerHTML = results[0].error;
            } else {
                format_openids(results);
            }
        }
    });
    return;
}

//Displays the openid list on the form
function format_openids(results) {
    OpenIDCount = 0;
    var value   = '';
    var html    = '';
    var i       = 0;

    results.each(function (hash) {
        html += '<tr><td align=right style=padding-left=12px>' +
                '<input type=radio onClick=$(\'loginDSubmit2\').disabled=false;' +
                '$(\'loginWarning\').hide();SelectedID=this.value; name=list ' +
                'value="'+hash.name+'" /></td>';

        for(i=0; i < hash.name.length; i+=36) {
            i==0 ? value = '' : value += '<br>';
            value += hash.name.substr(i,36);
        }

        html += '<td align=left><tt>'+value+'</tt></td></tr>';
        OpenIDCount++;
    });

    if(html == '') {
        $('loginWarning').innerHTML = '<tr><td colspan=2><br>There are no OpenIDs currently ' +
            'associated with this '+AppName+' Account.<br>' +
            '<a href=#add onClick=$(\'loginDList\').hide();$(\'loginDOpenid\').show();' +
                'edit_details(\'openid-add\')>Click here</a> to add one.</td></tr>';
    } else {
        $('loginDList').innerHTML = html;
        $('loginWarning').hide();
    }
    return;
}


//******************************************************************
// Account Confirmation Functions:
//******************************************************************

//Blanks out the screen and shows a confirmation window
function confirm_screen(confirm) {
    LoginPage   = 'main';
    UsingOpenID = false;
    var html = '<div style=border-bottom-style:solid;border-width:1px;' +
                 'padding-left:3px;padding-top:8px><b>Account Creation Confirmation</b></div>' +
               '<form id=loginMain method=post onSubmit=\'return false;\'>' +
               '<table id=loginTable cellspacing=0 cellpadding=3 align=center width=100%>' +
                 '<tr><td id=loginError colspan=3 align=center style=color:red;' +
                   'padding-bottom:3px>&nbsp; &nbsp;</td>' +
                   '<td id=loginWarning colspan=3 style=display:none;>Failed</td></tr>' +
                 '<tr><td colspan=3 align=center style=color:blue;padding-bottom:3px>' +
                   'Thank you for creating an account with '+AppName+', '+AppNameLong+'.' +
                   '<br><br>To complete the account creation process and to log into your '+AppName+' ' +
                   'account; please type in your username and click the "Continue" button below.' +
                 '<br><br></td></tr>' +
                 '<tr><td>Username:</td>' +
                   '<td><input align=right width=20% onKeyPress="if(event.keyCode==13){' +
                     '$(\'loginSubmit\').disabled=true;confirm_update($(\'loginUser\').'+
                       'getValue(),\'' + confirm + '\');return false;}" ' +
                       'id=loginUser type=text style=font-size:9pt size=20></td>' +
                   '<td align=center padding-top:3px>' +
                     '<input id=loginSubmit style=font-size:90% type=button value=\'Continue\'' +
                       'onClick=this.disabled=true;' +
                       'confirm_update($(\'loginUser\').getValue(),\'' + confirm + '\'); />' +
                 '</td></tr>' +
               '</table></font>' +
	       '<img id="loginBusy" src="/gbrowse2/images/spinner.gif" style="display:none;float:left" />' +
	       '</form>';

    login_blackout(true,html);
    return;
}

//Checks to make sure the username provided is the correct one and updates the account
function confirm_update(username, confirm) {
    if(username == '') {
        $('loginError').innerHTML = 'You must type in your username to continue.';
        $('loginSubmit').disabled = false;
    } else {
        $('loginError').innerHTML = '&nbsp; &nbsp;';
	$('loginBusy').show();
        new Ajax.Request(LoginScript,{
            method:      'post',
            parameters:  {action: ['confirm_account'],
                          user:    username,
                          confirm: confirm
            },
            onSuccess: function (transport) {
	        $('loginBusy').hide();
                var session = transport.responseText;
                if(session==''){session='Error: An error occurred while sending your request, please try again.';}
                confirm_check(username,session);
            }
        });
    }
    return;
}

//If an error occured while trying to confirm the username, this function displays that
function confirm_check(username,session) {
    if(session.indexOf('Error:')!=-1) {
        $('loginError').innerHTML = session;
        $('loginError').show();
        $('loginSubmit').disabled = false;
    } else if(session.indexOf('Already Active')!=-1) {
        $('loginTable').innerHTML = '<tr><td id=loginError colspan=3 align=center style=color:red;' +
            'padding-bottom:3px><br><br>The link provided is either incorrect or expired.' +
                '<br> Please click continue to exit.<br><br></td></tr>' +
            '<tr><td align=center padding-top:3px>' +
                '<input style=font-size:90% type=button value=\'Continue\'' +
                    'onClick=this.disabled=true;reload_login_script(); />' +
            '</td></tr>';
    } else {
        login_get_account(username,session,0,false);
    }
    return;
}

//Reloads the page without any options
function reload_login_script() {
    var urlString = String(document.location).split('?');
    document.location.href = urlString[0];
    return;
}


//******************************************************************
// Delete Account Function:
//******************************************************************

//Deletes a user from an account provided the username and pass are correct
function login_delete_user(username,pass) {
    $('loginBusy').show();
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['delete_user'],
                      user:    username,
                      pass:    pass
                     },
        onSuccess: function (transport) {
	    $('loginBusy').hide();
            $('loginWarning').innerHTML = transport.responseText;
            if($('loginWarning').innerHTML=='Success') {
                if(Logged) {
                    var urlString = String(document.location).split('?');
                        urlString = String(urlString[0]).split('#');
                    document.location.href = urlString[0] + '?id=logout';
                } else {
                    edit_details('home');
                    login_page_change('main');
                }
            } else {
                $('loginWarning').show();
                login_loading(false);
            }
        }
    });
    return;
}


//******************************************************************
// Function to Blackout Screen:
//******************************************************************

//Adapted from http://www.hunlock.com/blogs/Snippets:_Howto_Grey-Out_The_Screen
function login_blackout(turnOn,text) {
    var html    = text;
    var screen  = document.getElementById('loginConfirmScreen');
    var text    = document.getElementById('loginConfirmText');
    if(!screen) {
        var contents = document.getElementsByTagName('body')[0];
        var div      = document.createElement('div');
            div.id                    = 'loginConfirmScreen';
            div.style.backgroundColor = '#000000';
            div.style.display         = 'none';
            div.style.filter          = 'alpha(opacity=70)';
            div.style.height          = '100%';
            div.style.left            = '0px';
            div.style.MozOpacity      = '0.7';
            div.style.opacity         = '0.7';
            div.style.overflow        = 'hidden';
            div.style.position        = 'absolute';
            div.style.top             = '0px';
            div.style.width           = '100%';
            div.style.zIndex          = '50';

        var msg = document.createElement('div');
            msg.id                    = 'loginConfirmText';
            msg.innerHTML             =  html;
            msg.style.backgroundColor = '#DCDCDC';
            msg.style.border          = '#000 solid 1px';
            msg.style.bottom          = '0px';
            msg.style.height          = '220px';
            msg.style.left            = '0px';
            msg.style.margin          = 'auto';
            msg.style.overflow        = 'hidden';
            msg.style.position        = 'absolute';
            msg.style.right           = '0px';
            msg.style.textAlign       = 'center';
            msg.style.top             = '0px';
            msg.style.width           = '380px';
            msg.style.zIndex          = '60';

        contents.appendChild(msg);
        contents.appendChild(div);

        screen = document.getElementById('loginConfirmScreen');
        text   = document.getElementById('loginConfirmText');
    }

    if(turnOn) {
        document.body.style.overflow = 'hidden';
        screen.style.display         = 'block';

        if(html != '') {
            text.style.display = 'block';
        } else {
            text.style.display = 'none';
        }
    } else {
        document.body.style.overflow = 'auto';
        screen.style.display         = 'none';
        text.style.display           = 'none';
    }
}



