var LoginScript = "/cgi-bin/gb2/gbrowse_login"
var LoginPage   = "main";
var Logged      = false;

var SessionID, CurrentUser, EditDetails;

function load_login_balloon(event, session, username) {
    SessionID = session;
    var html = '<form id=loginMain method=post action=\'return false;\'>' +

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
                   '<tr id=loginDSelect style=display:none;><td colspan=2 align=center ' +
                     'style=padding-bottom:3px;padding-top:3px>' +
                     '<input id=loginChgEmail style=font-size:90% type=button value=\'Change my E-mail\'' +
                       'onClick=edit_details(\'email\') /><br>' +
                     '<input id=loginChgPass style=font-size:90% type=button value=\'Change my Password\'' +
                       'onClick=edit_details(\'password\') /></td></tr>' +

                   //Input text boxes
                   '<tr id=loginURow><td>Username:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){validate_info();} ' +
                       'id=loginUser type=text style=font-size:9pt size=20></td></tr>' +
                   '<tr id=loginERow style=display:none><td>E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){validate_info();} ' +
                       'id=loginEmail type=text style=font-size:9pt size=20></td></tr>' +
                   '<tr id=loginPRow><td>Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){validate_info();} ' +
                       'id=loginPass type=password style=font-size:9pt size=20></td></tr>' +
                   '<tr id=loginP2Row style=display:none><td>Retype Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){validate_info();} ' +
                       'id=loginPass2 type=password style=font-size:9pt size=20></td></tr>' +
                 '</tbody>' +

                   //"Edit Details" input text boxes
                 '<tbody id=loginDEmail style=display:none;>' +
                   '<tr><td width=40%>Current E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                     'id=loginDEOrig type=text style=font-size:9pt size=18></td></tr>' +
                   '<tr><td width=40%>New E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                     'id=loginDENew type=text style=font-size:9pt size=18></td></tr>' +
                   '<tr><td width=40%>Retype New E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                     'id=loginDENew2 type=text style=font-size:9pt size=18></td></tr>' +
                 '</tbody>' +
                 '<tbody id=loginDPass style=display:none;>' +
                   '<tr><td>Current Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                       'id=loginDPOrig type=password style=font-size:9pt size=18></td></tr>' +
                   '<tr><td>New Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                       'id=loginDPNew type=password style=font-size:9pt size=18></td></tr>' +
                   '<tr><td>Retype New Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                       'id=loginDPNew2 type=password style=font-size:9pt size=18></td></tr>' +
                 '</tbody>' +

                   //Submit, remember me and cancel buttons
                 '<tbody>' +
                   '<tr><td id=loginButtons colspan=2 align=center style=padding-bottom:3px;padding-top:6px>' +
                     '<input id=loginSubmit style=font-size:90% type=button value=\'Log in\'' +
                       'onClick=validate_info() />' +
                     '<b id=loginBreak>&nbsp; &nbsp;</b>' +
                     '<input id=loginRemember type=checkbox checked>' +
                       '<font id=loginRememberTxt>Remember me</font></input>' +
                     '<input id=loginCancel style=font-size:90%;display:none type=button value=\'Cancel\'' +
                       'onClick=login_page_change(\'main\') /></td></tr>' +

                   '<tr><td id=loginSpacing colspan=2 align=center style=display:none;' +
                     'padding-bottom:3px;padding-top:6px><b>&nbsp; &nbsp;</b></td></tr>' +

                   //"Edit Details" submit and cancel buttons
                   '<tr><td id=loginDButtons colspan=2 align=center style=display:none;' +
                     'padding-bottom:3px;padding-top:3px>' +
                     '<input id=loginDSubmit style=font-size:90% type=button value=\'Submit\'' +
                       'onClick=edit_details_verify() />&nbsp; &nbsp;' +
                     '<input id=loginDCancel style=font-size:90% type=button value=\'Cancel\'' +
                       'onClick=edit_details(\'home\') /></td></tr>' +

                   //Click here to Edit Details
                   '<tr id=loginOpts align=center><td colspan=2><font size=1>' +
                     '<a href=# onClick=login_page_change(\'create\');return false;>Register</a> / ' +
                     '<a href=# onClick=login_page_change(\'edit\');return false;>My Account</a> / ' +
                     '<a href=# onClick=login_page_change(\'forgot\');return false;>Forgotten Password?</a>' +
                   '</font></td></tr>' +

                   '<tr><td id=loginOpenID colspan=2 align=center style=padding-top:12px>' +
                     'Have an OpenID? <a href=?id=logout>Sign in</a>.</td></tr>' +
                 '</tbody>' +
               '</table></font></form>';

    GBox.showTooltip(event,html,1,320);

    if(username != false) {
        Logged = true;
        CurrentUser = username;
        login_page_change('edit');
        edit_details('home');
        $('loginMain').style.width = '260px'
    }
//Remove these lines
$('loginWarning').innerHTML = SessionID;
$('loginWarning').show();
//Remove these lines
}

function login_page_change(page) {
    LoginPage = page;
    $('loginPass').value = '';
    $('loginPass2').value = '';
    $('loginWarning').hide();

    switch(page) {
    case 'main':
        $('loginWarning').style.color = 'red';
        $('loginTitle').innerHTML     = 'Log in';
        $('loginSubmit').value        = 'Log in';
        $('loginCancel').value        = 'Cancel';
        $('loginSubmit').show();
        $('loginERow').hide();
        $('loginP2Row').hide();
        $('loginDSelect').hide();
        break;
    case 'create':
        $('loginTitle').innerHTML = 'Sign up';
        $('loginSubmit').value    = 'Sign up';
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
        break;
    default:
        return;
    }

    if(page == 'main') {
        $('loginOpts').show(); $('loginCancel').hide();
        $('loginOpenID').show(); $('loginRemember').show();
        $('loginRememberTxt').show();
    } else {
        $('loginOpts').hide(); $('loginCancel').show();
        $('loginOpenID').hide(); $('loginRemember').hide();
        $('loginRememberTxt').hide();
    }

    if(page =='forgot') {
        $('loginEmail').focus(); $('loginBreak').hide();
        $('loginURow').hide(); $('loginPRow').hide();
    } else {
        $('loginUser').focus(); $('loginBreak').show();
        $('loginURow').show(); $('loginPRow').show();
    }

    if((page == 'main') || (page == 'create')) {
        $('loginTable').style.paddingTop = '3px';
        $('loginButtons').style.paddingTop = '3px';
    } else {
        $('loginTable').style.paddingTop = '18px';
        $('loginButtons').style.paddingTop = '18px';
    }
}

function validate_info() {
    var user  = $('loginUser').getValue().length;
    var email = $('loginEmail').getValue().length;
    var pass  = $('loginPass').getValue();
    var pass2 = $('loginPass2').getValue();

    switch(LoginPage) {
    case 'create':
        if(user==0 || email==0 || pass.length==0 || pass2.length==0) {
            $('loginWarning').innerHTML = 'All fields are required.';
            $('loginWarning').show();
        } else if(pass != pass2) {
            $('loginWarning').innerHTML = 'Passwords do not match.';
            $('loginWarning').show();
        } else {
            add_user();
        }
        return;
    case 'forgot':
        if(email==0) {
            $('loginWarning').innerHTML = 'All fields are required.';
            $('loginWarning').show();
        } else {
            email_user_info()
        }
        return;
    default:
        if(user==0 || pass.length==0) {
            $('loginWarning').innerHTML = 'All fields are required.';
            $('loginWarning').show();
        } else {
            login_validation();
        }
        return;
    }
}


//******************************************************************
// Create New User Code:
//******************************************************************

function add_user() {
    var username = $('loginUser').getValue();
    var password = $('loginPass').getValue();
    var email    = $('loginEmail').getValue();

    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['add_user'],
                      user:     username,
                      email:    email,
                      pass:     password,
                      session:  SessionID
                     },
        onSuccess: function (transport) {
            $('loginWarning').innerHTML = transport.responseText;

            if($('loginWarning').innerHTML == '') {
                $('loginWarning').innerHTML = "Error: Cannot connect to mail " +
                    "server, an account has not been created.";
            }

            if($('loginWarning').innerHTML == "Session Error") {
                $('loginCancel').value        = 'Back';
                $('loginWarning').innerHTML = "Sorry, a user has already been created " +
                    "for the current session.<br><br>Please log in with that account or<br>" +
                    "<a href=# onClick=" +
                        "$('balloon').hide();$('closeButton').hide();LoginPage=\'main\';" +
                        "$(\'loginWarning\').innerHTML=\'Success\';" +
                        "login_user(\'none\',\'gbrowse_reset\');return false;>" +
                    "click here</a> to create a new session.";

                $('loginURow').hide(); $('loginERow').hide();  $('loginSubmit').hide();
                $('loginPRow').hide(); $('loginP2Row').hide(); $('loginWarning').show();
            } else {
                login_user(username);
            }
        }
    });
}


//******************************************************************
// Log In Validation Code:
//******************************************************************

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

    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['validate'],
                      user:     username,
                      pass:     password,
                      remember: remember
                     },
        onSuccess: function (transport) {
            var results = transport.responseText;
            if(results.indexOf("session")!=-1) {
                session = results.slice(7);
                $('loginWarning').innerHTML = "Success";
            } else {
                $('loginWarning').innerHTML = results;
            }
            login_user(username,session);
        }
    });
}

function login_user(username,session) {
    if ($('loginWarning').innerHTML != "Success") {
        $('loginWarning').show();
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
            $('loginWarning').innerHTML   = "A confirmation e-mail has been sent, please " +
                "follow the attached link to complete the registration process.";

            $('loginURow').hide(); $('loginERow').hide(); $('loginBreak').hide(); 
            $('loginPRow').hide(); $('loginP2Row').hide(); $('loginSubmit').hide();
            $('loginWarning').show();
            return;
        case 'main':
            new Ajax.Request(document.URL,{
                method:      'post',
                parameters: {authorize_login: 1,
                             username: username,
                             id:       session,
                             old_id:   SessionID
                            },
                onSuccess: function(transport) {
                    var results = transport.responseJSON;
                    if (results.id != null) {
                        login_load_account(location.href,results);
                    }
                }
            });
        }
    }
}

function login_load_account(to,p) {
    for (var k in p) {
    var myInput = document.createElement("input");
        myInput.setAttribute("name", k);
        myInput.setAttribute("value", p[k]);
        myInput.style.display = 'none';
        $('loginMain').appendChild(myInput);
    }
    $('loginMain').action = to;
    $('loginMain').submit();
}


//******************************************************************
// Forgot Password Code:
//******************************************************************

function email_user_info() {
    var email = $('loginEmail').getValue();

    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['email_info'],
                      email: email,
                     },
        onSuccess: function (transport) {
            var result = transport.responseText
            if(result != "Success") {
                if(result == '') {
                    $('loginWarning').innerHTML = "Error: Cannot connect to mail " +
                        "server, your information has not been sent.";
                } else {
                    $('loginWarning').innerHTML = result;
                }
                $('loginWarning').show();
            } else {
                $('loginCancel').value        = 'Back';
                $('loginWarning').style.color = 'blue';
                $('loginWarning').innerHTML = "A message has been sent to your" +
                    " e-mail address with your profile information.<br><br>" +
                    "Please follow the instructions provided to retrieve" +
                    " your account.";

                $('loginERow').hide();  $('loginSubmit').hide();
                $('loginBreak').hide(); $('loginWarning').show();
            }
        }
    });
}


//******************************************************************
// Change Account E-mail/Password Code:
//******************************************************************

function edit_details(details) {
    $('loginWarning').hide();

    if(details == 'home') {
        $('loginMain').reset();
        $('loginTitle').innerHTML = 'Edit account details';
        $('loginCancel').value = 'Go Back';
        $('loginTable').style.paddingTop = '18px';

        $('loginDButtons').hide(); $('loginDSelect').show(); 
        $('loginDEmail').hide();   $('loginSubmit').hide();
        $('loginBreak').hide();    $('loginDPass').hide();
        $('loginURow').hide();     $('loginPRow').hide();
        
        if(Logged == false) {$('loginButtons').show(); $('loginSpacing').hide();}
        else {$('loginButtons').hide(); $('loginSpacing').show();}
        return;
    } else {
        $('loginTable').style.paddingTop = '3px';
        $('loginWarning').style.color = 'red';
        $('loginCancel').value = 'Cancel';
        $('loginDSelect').hide();  $('loginButtons').hide();
        $('loginDButtons').show(); $('loginSpacing').hide();
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
    default:
        return;
    }
}

function edit_details_verify() {
    var old_email  = $('loginDEOrig').getValue();
    var new_email  = $('loginDENew').getValue();
    var new_email2 = $('loginDENew2').getValue();

    var old_pass  = $('loginDPOrig').getValue();
    var new_pass  = $('loginDPNew').getValue();
    var new_pass2 = $('loginDPNew2').getValue();

    if(EditDetails == 'email') {
        if(old_email.length==0 || new_email.length==0 || new_email2.length==0) {
            $('loginWarning').innerHTML = 'All fields are required.';
            $('loginWarning').show();
        } else if(new_email != new_email2) {
            $('loginWarning').innerHTML = 'New e-mails do not match. Please check your spelling.';
            $('loginWarning').show();
        } else {
            edit_details_submit(CurrentUser,'email',old_email,new_email);
        }
    } else {
        if(old_pass.length==0  || new_pass.length==0  || new_pass2.length==0) {
            $('loginWarning').innerHTML = 'All fields are required.';
            $('loginWarning').show();
        } else if(new_pass != new_pass2) {
            $('loginWarning').innerHTML = 'New passwords do not match. Please check your spelling.';
            $('loginWarning').show();
        } else {
            edit_details_submit(CurrentUser,'pass',old_pass,new_pass);
        }
    }
    return;
}

function edit_details_submit(username,column,old_val,new_val) {  
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['edit_details'],
                      user:    username,
                      column:  column,
                      old_val: old_val,
                      new_val: new_val
                     },
        onSuccess: function (transport) {
            $('loginWarning').innerHTML = transport.responseText;
            edit_details_confirm(column);
        }
    });
}

function edit_details_confirm(column) {
    if ($('loginWarning').innerHTML != "Success") {
        $('loginWarning').show();
    } else {
        $('loginWarning').style.color = 'blue';

        if(column == 'email') {
            $('loginWarning').innerHTML = 'Your e-mail has been changed successfully.';
        } else {
            $('loginWarning').innerHTML = 'Your password has been changed successfully.';
        }

        edit_details('home');
        $('loginWarning').show();
    }
}


//******************************************************************
// Account Confirmation Code:
//******************************************************************

function confirm_screen(confirm) {
    var screen = document.getElementById('loginConfirmScreen');
    var text   = document.getElementById('loginConfirmText');

    if(!screen) {
        var html = '<div style=border-bottom-style:solid;border-width:1px;' +
                     'padding-left:3px;padding-top:8px><b>Account Creation Confirmation</b></div>' +
                   '<form id=loginMain method=post action=\'return false;\'>' +
                   '<table id=loginTable cellspacing=0 cellpadding=3 align=center width=100%>' +
                     '<tr><td id=loginWarning colspan=3 align=center style=color:red;' +
                       'padding-bottom:3px>&nbsp; &nbsp;</td></tr>' +
                     '<tr><td colspan=3 align=center style=color:blue;padding-bottom:3px>' +
                       'Thank you for creating an account with GBrowse, the generic genome browser.' +
                       '<br><br>To complete the account creation process and to log into your GBrowse ' +
                       'account; please type in your username and click the "Continue" button below.' +
                     '<br><br></td></tr>' +
                     '<tr><td>Username:</td>' +
                       '<td><input align=right width=20% onKeyPress=if(event.keyCode==13){' +
                         'confirm_update($(\'loginUser\').getValue(),\'' + confirm + '\');} ' +
                         'id=loginUser type=text style=font-size:9pt size=20></td>' +
                       '<td align=center padding-top:3px>' +
                         '<input style=font-size:90% type=button value=\'Continue\'' +
                           'onClick=confirm_update($(\'loginUser\').getValue(),\'' + confirm + '\'); />' +
                     '</td></tr>' +
                   '</table></font></form>';

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

    document.body.style.overflow = 'hidden';
    screen.style.display         = 'block';
    text.style.display           = 'block';
}

function confirm_update(username, confirm) {
    if(username == '') {
        $('loginWarning').innerHTML = 'You must type in your username to continue.';
    } else {
        $('loginWarning').innerHTML = '&nbsp; &nbsp;';
		new Ajax.Request(LoginScript,{
		    method:      'post',
		    parameters:  {action: ['confirm_account'],
		                  user:    username,
		                  confirm: confirm
		                 },
		    onSuccess: function (transport) {
		        var session = transport.responseText;
		        if(session.indexOf("Error:")!=-1) {
		            $('loginWarning').innerHTML = session;
                } else if(session.indexOf("Already Active")!=-1) {
                    $('loginTable').innerHTML = '<tr><td id=loginWarning colspan=3 align=center style=color:red;' +
                        'padding-bottom:3px><br><br>This user has already been activated.' +
                            '<br> Please click continue to exit.<br><br></td></tr>' +
                        '<tr><td align=center padding-top:3px>' +
                            '<input style=font-size:90% type=button value=\'Continue\'' +
                                'onClick=reload_login_script(); />' +
                        '</td></tr>';
		        } else {
                    $('loginWarning').hide();
		            $('loginWarning').innerHTML = "Success";
		        }
		        LoginPage = "main";
		        login_user(username,session)
		    }
		});
    }
}


function reload_login_script() {
    var urlString  = String(document.location).split('?');
    document.location.href = urlString[0];
}



