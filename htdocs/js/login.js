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
                 '<b id=loginTitle>' + Controller.translate('LOG_IN') + '</b></div>' +

               '<font face=Arial size=2>' +
               //Table containing login form
               '<table id=loginTable cellspacing=0 cellpadding=3 align=center width=100% style=padding-top:3px>' +
                 //Warning message
                 '<tbody><tr><td id=loginWarning colspan=2 align=center style=display:none;' +
                   'color:red;padding-bottom:3px>' + Controller.translate('ALL_FIELDS_REQUIRED') + 
                   '</td></tr></tbody>' +

                   //"Edit Details" selection buttons
                 '<tbody>' +
                   '<tr id=loginDSelect style=display:none;><td colspan=2 align=left>' +
                     '<ul style=\'margin:0px 0px 0px 18px\'>' +
                         '<li id=loginChgEmail><a href=#email onClick=edit_details(\'email\')>' +
                             Controller.translate('CHANGE_MY_EMAIL') + '</a></li>' +
                         '<li id=loginChgPass><a href=#pass onClick=edit_details(\'password\')>' +
                             Controller.translate('CHANGE_MY_PASSWORD') + '</a></li>' +
                         '<li><a href=#add onClick=edit_details(\'openid-add\')>' +
                             Controller.translate('ADD_OPENID') + '</a></li>' +
                         '<li><a href=#remove onClick=edit_details(\'openid-remove\')>' +
                             Controller.translate('LIST_REMOVE_OPENIDS') + '</a></li>' +
                         '<li><a href=#delete onClick=edit_details(\'delete\')>' +
                             Controller.translate('DELETE_MY_ACCOUNT') + '</a></li>' +
                   '</ul></td></tr>' +
                 '</tbody>' +

                   //Input text boxes
                 '<tbody id=loginNorm>' +
                   '<tr id=loginURow><td>' + Controller.translate('USERNAME') + '</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);validate_info();} ' +
                       'id=loginUser type=text maxlength=32 style=font-size:9pt size=20></td></tr>' +
                   '<tr id=loginERow style=display:none><td>' + Controller.translate('EMAIL_TO_VALIDATE') + '</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);validate_info();} ' +
                       'id=loginEmail type=text maxlength=64 style=font-size:9pt size=20></td></tr>' +
                   '<tr id=loginPRow><td>' + Controller.translate('PASSWORD') + '</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);validate_info();} ' +
                       'id=loginPass type=password maxlength=32 style=font-size:9pt size=20></td></tr>' +
                   '<tr id=loginP2Row style=display:none><td>' + Controller.translate('RETYPE_PASSWORD') + '</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);validate_info();} ' +
                       'id=loginPass2 type=password maxlength=32 style=font-size:9pt size=20></td></tr>' +
                 '</tbody>' +

                   //"Edit Details" input text boxes
                 '<tbody id=loginDEmail style=display:none;>' +
                   '<tr><td width=40%>' + Controller.translate('CURRENT_EMAIL') + '</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDEOrig type=text maxlength=64 style=font-size:9pt size=18></td></tr>' +
                   '<tr><td width=40%>' + Controller.translate('NEW_EMAIL') + '</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDENew type=text maxlength=64 style=font-size:9pt size=18></td></tr>' +
                   '<tr><td width=40%>' + Controller.translate('RETYPE_NEW_EMAIL') + '</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDENew2 type=text maxlength=64 style=font-size:9pt size=18></td></tr>' +
                 '</tbody>' +

                 '<tbody id=loginDPass style=display:none;>' +
                   '<tr><td>' + Controller.translate('CURRENT_PASSWORD') + '</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDPOrig type=password maxlength=32 style=font-size:9pt size=18></td></tr>' +
                   '<tr><td>' + Controller.translate('NEW_PASSWORD') + '</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDPNew type=password maxlength=32 style=font-size:9pt size=18></td></tr>' +
                   '<tr><td>' + Controller.translate('RETYPE_NEW_PASSWORD') + '</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){login_loading(true);edit_details_verify();} ' +
                       'id=loginDPNew2 type=password maxlength=32 style=font-size:9pt size=18></td></tr>' +
                 '</tbody>' +

                  //Password textbox for adding a new openid to an account
                 '<tbody id=loginDOpenidPass align=center style=display:none;>' +
                   '<tr><td colspan=2>' + Controller.translate('CURRENT_APP_PASSWORD',AppName) + '</td></tr>' +
                     '<tr><td colspan=2 style=padding-bottom:6px;><input onKeyPress=if(event.keyCode==13){' +
                       'login_loading(true);edit_details_verify();} id=loginDOPass type=password maxlength=32 ' +
                       'style=font-size:9pt size=24></td></tr>' +
                 '</tbody>' +
                  //Username textbox for adding a new openid to an openid only account
                 '<tbody id=loginDOpenidUser align=center style=display:none;>' +
                   '<tr><td colspan=2>' + Controller.translate('CURRENT_APP_USERNAME',AppName) + '</td></tr>' +
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
                       '<image onClick=check_openid(\'https://www.google.com/accounts/o8/id\'); ' +
                         'src='+ImgLocation+'/google-logo.gif alt=\'Google\' height=20px width=20px>' +
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
                     '<input id=loginSubmit style=font-size:90% type=button value=\'' + Controller.translate('LOG_IN') + '\'' +
                       'onClick=login_loading(true);$(\'loginWarning\').hide();validate_info(); />' +
                     '<b id=loginBreak>&nbsp; &nbsp;</b>' +
                     '<input id=loginRemember type=checkbox checked>' +
                       '<font id=loginRememberTxt>' + Controller.translate('REMEMBER_ME') + '</font></input>' +
                     '<input id=loginCancel style=font-size:90%;display:none type=button value=\'' + Controller.translate('CANCEL') + '\'' +
                       'onClick=login_page_change(\'main\') /></td></tr>' +

                   '<tr><td id=loginSpacing colspan=2 style=display:none><br></td></tr>' +

                    //"Edit Details" submit and cancel buttons
                   '<tr><td id=loginDButtons colspan=2 align=center style=display:none;' +
                     'padding-bottom:3px;padding-top:3px>' +
                     '<input id=loginDSubmit2 style=font-size:90% type=button value=\'' + Controller.translate('REMOVE') + '\'' +
                       'onClick=edit_details(\'openid-remove-verify\'); />' +
                     '<input id=loginDSubmit style=font-size:90% type=button value=\'' + Controller.translate('SUBMIT') + '\'' +
                       'onClick=login_loading(true);$(\'loginWarning\').hide();edit_details_verify(); />' +
                     '&nbsp; &nbsp;' +
                     '<input id=loginDCancel style=font-size:90% type=button value=\'' + Controller.translate('CANCEL') + '\'' +
                       'onClick=edit_details(\'home\') /></td></tr>' +

                    //Register, My Account and Forgotten Password selections
                   '<tr id=loginOpts align=center><td id=loginOptsContent1 colspan=2><font size=1>' +
                     '<a href=#register onClick=login_page_change(\'create\');>' + Controller.translate('REGISTER') + '</a> / ' +
                     '<a href=#account onClick=login_page_change(\'edit\');>' + Controller.translate('MY_ACCOUNT') + '</a> / ' +
                     '<a href=#forgot onClick=login_page_change(\'forgot\');>' + Controller.translate('FORGOTTEN_PASSWORD') + '</a>' +
                   '</font></td>' +
                   '<td id=loginOptsContent2 colspan=2 style=display:none;><font size=1>' +
                      Controller.translate('REGISTER') + ' / ' + Controller.translate('MY_ACCOUNT') + ' / ' + Controller.translate('FORGOTTEN_PASSWORD') + '</font></td>' +
                   '</tr>' +
                 '</tbody>' +

                  //Switch between regular and openid login pages
                 '<tbody id=loginOpenID>' +
                   '<tr><td id=loginOpenIDY colspan=2 align=center style=padding-top:12px>' +
                       Controller.translate('HAVE_OPENID') + ' <a href=#openid onClick=login_page_openid(true)>' +
                       Controller.translate('SIGN_IN') + '</a></td></tr>' +
                   '<tr><td id=loginOpenIDN colspan=2 align=center style=display:none;padding-top:12px>' +
                       Controller.translate('DONT_HAVE_OPENID') + ' <a href=#noopenid onClick=login_page_openid(false)>' +
                       Controller.translate('GO_BACK') + '</a></td></tr>' +
                 '</tbody>' +
               '</table></font>'+
               '<img id="loginBusy" src="'+Controller.button_url('spinner.gif')+'" style="display:none;float:left" />' +
	       '&nbsp;<a style="float:right;font-size:90%" href="javascript:void(0)" '+
	                'onClick="Balloon.prototype.hideTooltip(1)">' + Controller.translate('CLOSE') + '</a>' +
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
        $('loginTitle').innerHTML     = Controller.translate('LOG_IN');
        $('loginSubmit').value        = Controller.translate('LOG_IN');
        $('loginCancel').value        = Controller.translate('CANCEL');
        $('loginOpenID').blur();
        $('loginOpts').blur();
        $('loginOpenID').show();
        $('loginERow').hide();  $('loginSubmit').show();
        $('loginP2Row').hide(); $('loginDSelect').hide();
        break;
    case 'create':
        $('loginTitle').innerHTML = Controller.translate('REGISTER');
        $('loginSubmit').value    = Controller.translate('REGISTER');
        $('loginERow').show();
        $('loginP2Row').show();
        break;
    case 'forgot':
        $('loginTitle').innerHTML = Controller.translate('FORGOT_MY_PASSWORD');
        $('loginSubmit').value    = Controller.translate('EMAIL_MY_PASSWORD');
        $('loginERow').show();
        break;
    case 'edit':
        $('loginTitle').innerHTML = Controller.translate('EDIT_ACCOUNT_DETAILS');
        $('loginSubmit').value    = Controller.translate('CONTINUE');
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

        $('loginOpenIDY').innerHTML = Controller.translate('HAVE_OPENID')      + ' ' + Controller.translate('SIGN_IN');
        $('loginOpenIDN').innerHTML = Controller.translate('DONT_HAVE_OPENID') + ' ' + Controller.translate('GO_BACK');
    } else {
        $('loginSubmit').disabled  = false;  $('loginCancel').disabled  = false;
        $('loginDSubmit').disabled = false;  $('loginDCancel').disabled = false;
        $('loginOptsContent1').show();       $('loginOptsContent2').hide();

        $('loginOpenIDY').innerHTML = Controller.translate('HAVE_OPENID') + ' <a href=#openid onClick=' +
                                      'login_page_openid(true)>' + Controller.translate('SIGN_IN') + '</a>';
        $('loginOpenIDN').innerHTML = Controller.translate('DONT_HAVE_OPENID') + ' <a href=#noopenid onClick=' +
                                      'login_page_openid(false)>' + Controller.translate('GO_BACK') + '</a>.';
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
            $('loginWarning').innerHTML = Controller.translate('ALL_FIELDS_REQUIRED');
        } else if(pass != pass2) {
            $('loginWarning').innerHTML = Controller.translate('PASSWORDS_DO_NOT_MATCH');
        } else {
            add_user();
            return;
        }
        break;
    case 'forgot':
        if(email==0) {$('loginWarning').innerHTML = Controller.translate('ALL_FIELDS_REQUIRED');}
        else {email_user_info();return;}
        break;
    case 'new-openid':
        if(user==0) {
            $('loginWarning').innerHTML = Controller.translate('ALL_FIELDS_REQUIRED') + '<br>' + html;
        } else {
            add_openid_user(CurrentUser,html);
            return;
        }
        break;
    default:
        if(OpenIDMenu) {
            if(openid.length==0 || openid=='http://' || openid=='https://' || openid.indexOf('.')==-1) {
                $('loginWarning').innerHTML = Controller.translate('TYPE_PROPER_OPENID');
            } else {
                check_openid(openid);
                return;
            }
        } else {
            if(user==0 || pass.length==0) {
                $('loginWarning').innerHTML = Controller.translate('ALL_FIELDS_REQUIRED');
            } else {
                login_validation();
                return;
            }
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
                $('loginWarning').innerHTML = Controller.translate('CANNOT_CONNECT_MAIL');
            }

            if(results=='Session Error' || results == 'E-mail in use' || results=='Message Already Sent') {
                login_loading(false);
                $('loginCancel').value = Controller.translate('BACK');

                if(results == 'Session Error') {
                    $('loginWarning').innerHTML = Controller.translate('USER_ALREADY_CREATED') +
                            '<a href=#reset onClick="$(\'balloon\').hide();$(\'closeButton\').hide();' +
                            'login_get_account(\'Reset\',\'Reset\',0,false);return false;">' +
                            Controller.translate('CREATE_NEW_SESSION') + '</a>' ;
                } else if(results == 'E-mail in use') {
                    $('loginWarning').innerHTML = Controller.translate('EMAIL_ALREADY_USED', AppName) + 
                            ' <a href=#forgot onClick="login_page_change(\'main\');' +
                            'login_page_change(\'forgot\');login_loading(true);' +
                            'email_user_info();return false;">' + Controller.translate('FORGOTTEN_PASSWORD') + '</a>.';
                } else if(results == 'Message Already Sent') {
                    var link1 = '<a href=#resend onClick="edit_confirmation(1);return false;">' + Controller.translate('RESEND_CONFIRM_EMAIL') + '</a>';
                    var link2 = '<a href=#remove onClick="edit_confirmation(0);return false;">' + Controller.translate('DELETE_UNCONFIRMED')   + '</a>';
                    $('loginWarning').innerHTML = Controller.translate('MESSAGE_ALREADY_SENT', link1, link2);
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

//Adds the user to the database if they didn't previously exist (openid login)
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
                $('loginCancel').value      = Controller.translate('BACK');
                $('loginWarning').innerHTML = Controller.translate('USER_ALREADY_CREATED') + 
                    '<a href=#reset onClick="$(\'balloon\').hide();$(\'closeButton\').hide();' +
                      'login_get_account(\'Reset\',\'Reset\',0,false);return false;">' +
                    Controller.translate('CREATE_NEW_SESSION') + '</a>' ;

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
            $('loginCancel').value        = Controller.translate('BACK');
            $('loginWarning').style.color = 'blue';
            $('loginWarning').innerHTML   = Controller.translate('CONFIRMATION_EMAIL_SENT');

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
    $('loginWarning').innerHTML = Controller.translate('ANOTHER_ACCOUNT_IN_USE');
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
                    $('loginWarning').innerHTML = Controller.translate('CANNOT_CONNECT_NOT_SENT');
                } else {
                    $('loginWarning').innerHTML = result;
                }
                $('loginWarning').show();
            } else {
                $('loginCancel').value        = Controller.translate('BACK');
                $('loginWarning').style.color = 'blue';
                $('loginWarning').innerHTML = Controller.translate('PROFILE_EMAIL_SENT');
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
        $('loginTitle').innerHTML = Controller.translate('EDIT_ACCOUNT_DETAILS');
        $('loginCancel').value    = Controller.translate('GO_BACK');
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
        $('loginDCancel').value          = Controller.translate('CANCEL');
        $('loginDSubmit').value          = Controller.translate('SUBMIT');
        login_loading(false);

        $('loginDSelect').hide();  $('loginButtons').hide();
        $('loginDButtons').show(); $('loginSpacing').hide();
        $('loginDSubmit2').hide(); $('loginDSubmit').show();  
    }  

    switch(details) {
    case 'email':
        $('loginTitle').innerHTML = Controller.translate('CHANGE_MY_EMAIL');
        $('loginDEmail').show();
        $('loginDEOrig').focus();
        EditDetails = 'email';
        return;
    case 'password':
        $('loginTitle').innerHTML = Controller.translate('CHANGE_MY_PASSWORD');
        $('loginDPass').show();
        $('loginDPOrig').focus();
        EditDetails = 'password';
        return;
    case 'openid-add':
        $('loginTitle').innerHTML = Controller.translate('ADD_OPENID');
        EditDetails = 'openid-add';
        $('loginDOpenid').show();
        if(UsingOpenID) {$('loginDOpenidUser').show(); $('loginDOUser').focus();}
        else {$('loginDOpenidPass').show(); $('loginDOPass').focus();}
        return;
    case 'openid-remove':
        $('loginDList').innerHTML   = '<tr><td></td></tr>';
        $('loginTitle').innerHTML   = Controller.translate('REMOVE_OPENID');
        $('loginDSubmit2').disabled = true;
        $('loginDList').show();
        $('loginDSubmit').hide();
        $('loginDSubmit2').show();
        EditDetails = 'openid-remove';
        list_openid();
        return;
    case 'openid-remove-verify':
        if(UsingOpenID && OpenIDCount == 1) {
            $('loginWarning').innerHTML = Controller.translate('NEED_OPENID_TO_ACCESS', AppName);
            $('loginWarning').show();
            $('loginDSubmit').hide();
            $('loginDSubmit2').show();
            $('loginDSubmit2').disabled = true;
        } else {
            $('loginTitle').innerHTML = Controller.translate('CONFIRM_ACCOUNT_PASSWORD');
            $('loginDList').hide();
            if(UsingOpenID) {$('loginDOpenidUser').show(); $('loginDOUser').focus();}
            else {$('loginDOpenidPass').show(); $('loginDOPass').focus();}
        }
        return;
    case 'delete':
        $('loginTitle').innerHTML   = Controller.translate('ARE_YOU_SURE');
        $('loginWarning').innerHTML = Controller.translate('WARNING_DELETE_OPENID',AppName,AppName);
        $('loginWarning').show();
        $('loginDCancel').value = Controller.translate('NO');
        $('loginDSubmit').value = Controller.translate('YES');
        EditDetails = 'delete';
        return;
    case 'delete-confirm':
        $('loginTitle').innerHTML   = Controller.translate('CONFIRM_ACCOUNT_DELETE');
        $('loginWarning').innerHTML = Controller.translate('WARNING_IRREVERSIBLE');
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
            $('loginWarning').innerHTML = Controller.translate('ALL_FIELDS_REQUIRED');
        } else if(new_email != new_email2) {
            $('loginWarning').innerHTML = Controller.translate('NEW_EMAILS_DIFFERENT');
        } else {
            edit_details_submit(CurrentUser,'email',old_email,new_email);
            return;
        }
        break;
    case 'password':
        if(old_pass.length==0  || new_pass.length==0  || new_pass2.length==0) {
            $('loginWarning').innerHTML = Controller.translate('ALL_FIELDS_REQUIRED');
        } else if(new_pass != new_pass2) {
            $('loginWarning').innerHTML = Controller.translate('NEW_PASSWORDS_DIFFERENT');
        } else {
            edit_details_submit(CurrentUser,'pass',old_pass,new_pass);
            return;
        }
        break;
    case 'openid-add':
        if(openid.length==0 || (!UsingOpenID && opass.length==0) || (UsingOpenID && ouser.length==0)) {
            $('loginWarning').innerHTML = Controller.translate('ALL_FIELDS_REQUIRED');
        } else if(UsingOpenID && CurrentUser != ouser) {
            $('loginWarning').innerHTML = Controller.translate('INCORRECT_USERNAME');
        } else {
            change_openid(CurrentUser,opass,openid,'add');
            return;
        }
        break;
    case 'openid-remove':
        if((!UsingOpenID && opass.length==0) || (UsingOpenID && ouser.length==0)) {
            $('loginWarning').innerHTML = Controller.translate('PLEASE_CONFIRM_INFO');
        } else if(UsingOpenID && CurrentUser != ouser) {
            $('loginWarning').innerHTML = Controller.translate('INCORRECT_USERNAME');
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
            $('loginWarning').innerHTML = Controller.translate('PLEASE_CONFIRM_INFO');
        } else if(UsingOpenID && CurrentUser != ouser) {
            $('loginWarning').innerHTML = Controller.translate('INCORRECT_USERNAME');
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
            case 'email': $('loginWarning').innerHTML = Controller.translate('EMAIL_CHANGE_SUCCESS');break;
            case 'password': $('loginWarning').innerHTML = Controller.translate('PASSWORD_CHANGE_SUCCESS');break;
            case 'openid-add': $('loginWarning').innerHTML = Controller.translate('OPENID_ADD_SUCCESS');break;
            case 'openid-remove': $('loginWarning').innerHTML = Controller.translate('OPENID_REMOVE_SUCCESS');break;
            default: $('loginWarning').innerHTML = Controller.translate('OPERATION_SUCCESS');break;
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
        $('loginCancel').value        = Controller.translate('BACK');
        $('loginSubmit').value        = Controller.translate('CREATE_ACCOUNT');
        $('loginWarning').innerHTML   = '<font /><font color=blue>' + Controller.translate('OPENID_NOT_ASSOC', AppName) + '</font>';

        $('loginRemember').hide();  $('loginRememberTxt').hide();
        $('loginWarning').show();   $('loginDOpenid').hide();
        $('loginOpenID').hide();    $('loginNorm').show();
        $('loginCancel').show();    $('loginPRow').hide();
        $('loginOpts').hide();      $('loginUser').focus();
    } else if(error == 'error') {
        $('loginWarning').innerHTML = Controller.translate('ANOTHER_ACCOUNT_IN_USE');
        $('loginWarning').show();
    } else if(page == 'edit') {
        $('loginWarning').innerHTML = error;
        if($('loginWarning').innerHTML == 'undefined') {$('loginWarning').innerHTML = Controller.translate('SUCCESS');}
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
    $('loginWarning').innerHTML = Controller.translate('LOADING');
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
        $('loginWarning').innerHTML = '<tr><td colspan=2><br>' + Controller.translate('NO_OPENIDS_ASSOCIATED', AppName) +
            '<a href=#add onClick=$(\'loginDList\').hide();$(\'loginDOpenid\').show();' +
                'edit_details(\'openid-add\')>' + Controller.translate('ADD_ONE') + '</a></td></tr>';
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
                 'padding-left:3px;padding-top:8px><b>' + Controller.translate('ACCOUNT_CREATION_CONF') + '</b></div>' +
               '<form id=loginMain method=post onSubmit=\'return false;\'>' +
               '<table id=loginTable cellspacing=0 cellpadding=3 align=center width=100%>' +
                 '<tr><td id=loginError colspan=3 align=center style=color:red;' +
                   'padding-bottom:3px>&nbsp; &nbsp;</td>' +
                   '<td id=loginWarning colspan=3 style=display:none;>Failed</td></tr>' +
                 '<tr><td colspan=3 align=center style=color:blue;padding-bottom:3px>' +
                   Controller.translate('THANKS_FOR_CREATING',AppName,AppNameLong,AppName) +
                 '<br><br></td></tr>' +
                 '<tr><td>' + Controller.translate('USERNAME') + '</td>' +
                   '<td><input align=right width=20% onKeyPress="if(event.keyCode==13){' +
                     '$(\'loginSubmit\').disabled=true;confirm_update($(\'loginUser\').'+
                       'getValue(),\'' + confirm + '\');return false;}" ' +
                       'id=loginUser type=text style=font-size:9pt size=20></td>' +
                   '<td align=center padding-top:3px>' +
                     '<input id=loginSubmit style=font-size:90% type=button value=\'' + Controller.translate('CONTINUE') + '\'' +
                       'onClick=this.disabled=true;' +
                       'confirm_update($(\'loginUser\').getValue(),\'' + confirm + '\'); />' +
                 '</td></tr>' +
               '</table></font>' +
               '<img id="loginBusy" src="'+Controller.button_url('spinner.gif') + '" style="display:none;float:left" />' +
	       '</form>';

    login_blackout(true,html);
    return;
}

//Checks to make sure the username provided is the correct one and updates the account
function confirm_update(username, confirm) {
    if(username == '') {
        $('loginError').innerHTML = Controller.translate('MUST_TYPE_USERNAME');
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
            'padding-bottom:3px><br><br>' + Controller.translate('INCORRECT_LINK') + '<br><br></td></tr>' +
            '<tr><td align=center padding-top:3px>' +
                '<input style=font-size:90% type=button value=\'' + Controller.translate('CONTINUE') + '\'' +
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



