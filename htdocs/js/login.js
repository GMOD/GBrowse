var LoginScript = "/cgi-bin/gb2/gbrowse_login"
var LoginPage   = "main";

var CurrentUser, CurrentPass;
var EditDetails;

function load_login_balloon(event) {
    var html = '<form id=loginMain method=post action=\'return false;\'>' +

               //Title at top of GBox
               '<div style=border-bottom-style:solid;border-width:1px;padding-left:3px>' +
                 '<b id=loginTitle>Log in</b></div>' +

               //Table containing login form
               '<table id=loginTable align=center style=font-size:small;padding-top:3px>' +
                 //Warning message
                 '<tbody><tr><td id=loginWarning colspan=2 align=center style=display:none;' +
                   'color:red;padding-bottom:3px>All fields are required.</td></tr></tbody>' +
                 //Click here to create a new account
                 '<tbody>' +
                   '<tr><td id=loginCreate colspan=2 align=center style=padding-bottom:3px>' +
                     'Don\'t have an account? <a href=# onClick=login_page_change(\'create\');' +
                       'return false;>Create one</a>.</td></tr>' +

                   //"Edit Details" selection buttons
                   '<tr id=loginDSelect style=display:none;><td colspan=2 align=center ' +
                     'style=padding-bottom:3px;padding-top:3px>' +
                     '<input id=loginChgEmail type=button value=\'Change my E-mail\'' +
                       'onClick=edit_details(\'email\') /><br>' +
                     '<input id=loginChgPass type=button value=\'Change my Password\'' +
                       'onClick=edit_details(\'password\') /></td></tr>' +

                   //Input text boxes
                   '<tr id=loginURow><td align=right>Username:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){validate_info();} ' +
                     'id=loginUser type=text size=15></td></tr>' +
                   '<tr id=loginERow style=display:none><td align=right>E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){validate_info();} ' +
                     'id=loginEmail type=text size=15></td></tr>' +
                   '<tr id=loginPRow><td align=right>Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){validate_info();} ' +
                     'id=loginPass type=password size=15></td></tr>' +
                   '<tr id=loginP2Row style=display:none><td align=right>Retype Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){validate_info();} ' +
                     'id=loginPass2 type=password size=15></td></tr>' +
                 '</tbody>' +

                   //"Edit Details" input text boxes
                 '<tbody id=loginDEmail style=display:none;>' +
                   '<tr><td align=right>Current E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                     'id=loginDEOrig type=text size=15></td></tr>' +
                   '<tr><td align=right>New E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                     'id=loginDENew type=text size=15></td></tr>' +
                   '<tr><td align=right>Retype New E-mail:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                     'id=loginDENew2 type=text size=15></td></tr>' +
                 '</tbody>' +
                 '<tbody id=loginDPass style=display:none;>' +
                   '<tr><td align=right>Current Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                     'id=loginDPOrig type=password size=15></td></tr>' +
                   '<tr><td align=right>New Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                     'id=loginDPNew type=password size=15></td></tr>' +
                   '<tr><td align=right>Retype New Password:</td>' +
                     '<td><input onKeyPress=if(event.keyCode==13){edit_details_verify();} ' +
                     'id=loginDPNew2 type=password size=15></td></tr>' +
                 '</tbody>' +

                   //Remember me button
                 '<tbody>' +
                   '<tr><td/><td id=loginRemember align=left><input type=checkbox checked ' +
                     'style=padding-bottom:3px>Remember me</input></td></tr>' +

                   //Submit and cancel buttons
                   '<tr><td id=loginButtons colspan=2 align=center style=padding-bottom:3px;padding-top:3px>' +
                     '<input id=loginSubmit type=button value=\'Log in\'' +
                       'onClick=validate_info() />' +
                     '<b id=loginBreak style=display:none>&nbsp; &nbsp;</b>' +
                     '<input id=loginCancel type=button value=\'Cancel\'' +
                       'onClick=login_page_change(\'main\') style=display:none /></td></tr>' +

                   //"Edit Details" submit and cancel buttons
                   '<tr><td id=loginDButtons colspan=2 align=center style=display:none;' +
                     'padding-bottom:3px;padding-top:3px>' +
                     '<input id=loginDSubmit type=button value=\'Submit\'' +
                       'onClick=edit_details_verify() />&nbsp; &nbsp;' +
                     '<input id=loginDCancel type=button value=\'Cancel\'' +
                       'onClick=edit_details(\'home\') /></td></tr>' +

                   //Click here to Edit Details
                   '<tr id=loginEdit><td colspan=2 align=center><a href=# ' +
                     'onClick=login_page_change(\'edit\');' +
                       'return false;>Edit account details</a></td></tr>' +

                   //Click here to retrive your password
                   '<tr id=loginForgot><td colspan=2 align=center><a href=# ' +
                     'onClick=login_page_change(\'forgot\');' +
                       'return false;>Forgot my password</a></td></tr>' +

                   '<tr><td id=loginOpenID colspan=2 align=center style=padding-top:12px>' +
                     'Have an OpenID? <a href=# onClick=login_page_change(\'create\');' +
                       'return false;>Sign in</a>.</td></tr>' +
                 '</tbody>' +
               '</table></form>';

    GBox.showTooltip(event,html,1,250);
}


function login_page_change(page) {
    LoginPage = page;
    $('loginWarning').hide();

    switch(page) {
    case 'main':
        $('loginWarning').style.color = 'red';
        $('loginTitle').innerHTML     = 'Log in';
        $('loginSubmit').value        = 'Log in';
        $('loginSubmit').show();
        $('loginERow').hide();
        $('loginP2Row').hide();
        $('loginBreak').hide();
        $('loginDSelect').hide();
        break;
    case 'create':
        $('loginTitle').innerHTML = 'Sign up';
        $('loginSubmit').value    = 'Sign up';
        $('loginERow').show();
        $('loginP2Row').show();
        $('loginBreak').show();
        $('loginEmail').size = '15';
        break;
    case 'forgot':
        $('loginTitle').innerHTML = 'Forgot my password';
        $('loginSubmit').value    = 'E-mail my password';
        $('loginERow').show();
        $('loginEmail').size = '18';
        break;
    case 'edit':
        $('loginTitle').innerHTML = 'Edit account details';
        $('loginSubmit').value    = 'Continue';
        $('loginBreak').show();
        break;
    default:
        return;
    }

    if(page == 'main') {
        $('loginEdit').show();   $('loginCancel').hide();
        $('loginCreate').show(); $('loginForgot').show();
        $('loginOpenID').show(); $('loginRemember').show();
    } else {
        $('loginEdit').hide();   $('loginCancel').show();
        $('loginCreate').hide(); $('loginForgot').hide();
        $('loginOpenID').hide(); $('loginRemember').hide();
    }

    if(page =='forgot') {
        $('loginEmail').focus();
        $('loginURow').hide(); $('loginPRow').hide();
    } else {
        $('loginUser').focus();
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


function login_validation() {
    var username = $('loginUser').getValue();
    var password = $('loginPass').getValue();

    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['validate'],
                      user:  username,
                      pass:  password
                     },
        onSuccess: function (transport) {
            $('loginWarning').innerHTML = transport.responseText;
            login_user(username,password);
        }
    });
}


function login_user(username,password) {
    if ($('loginWarning').innerHTML != "Success") {
        $('loginWarning').show();
        return;
    } else {
        CurrentUser = username;
        CurrentPass = password;

        if(LoginPage == 'edit') {
            edit_details('home');
            return;
        }

        $('loginWarning').innerHTML = "Gooood";
        $('loginWarning').show();

        //do_login_script();
    }
}


function add_user() {
    var username = $('loginUser').getValue();
    var password = $('loginPass').getValue();
    var email    = $('loginEmail').getValue();

    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['add_user'],
                      user:  username,
                      email: email,
                      pass:  password
                     },
        onSuccess: function (transport) {
            $('loginWarning').innerHTML = transport.responseText;
            login_user(username,password);
        }
    });
}



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
                $('loginWarning').innerHTML = result;
                $('loginWarning').show();
            } else {
                $('loginWarning').style.color = 'blue';
                $('loginWarning').innerHTML = "A message has been sent to your" +
                    " e-mail address with your profile information.";

                $('loginERow').hide();  $('loginSubmit').hide();
                $('loginBreak').hide(); $('loginWarning').show();
            }
        }
    });
}


function edit_details(details) {
    $('loginWarning').hide();

    if(details == 'home') {
        $('loginMain').reset();
        $('loginTitle').innerHTML = 'Edit account details';
        $('loginTable').style.paddingTop = '18px';

        $('loginDButtons').hide();
        $('loginDEmail').hide();   $('loginSubmit').hide();
        $('loginBreak').hide();    $('loginDPass').hide();
        $('loginURow').hide();     $('loginPRow').hide();
        
        $('loginDSelect').show();  $('loginButtons').show(); 
        return;
    } else {
        $('loginTable').style.paddingTop = '3px';
        $('loginWarning').style.color = 'red';
        $('loginDSelect').hide(); $('loginButtons').hide(); $('loginDButtons').show();
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
            retrieve_email(CurrentUser,CurrentPass,new_email,'email',old_email);
        }
    } else {
        if(old_pass.length==0  || new_pass.length==0  || new_pass2.length==0) {
            $('loginWarning').innerHTML = 'All fields are required.';
            $('loginWarning').show();
        } else if(old_pass != CurrentPass) {
            $('loginWarning').innerHTML = 'Incorrect password provided. Please check your spelling.';
            $('loginWarning').show();
        } else if(new_pass != new_pass2) {
            $('loginWarning').innerHTML = 'New passwords do not match. Please check your spelling.';
            $('loginWarning').show();
        } else {
            edit_details_submit(CurrentUser,CurrentPass,new_pass,'pass');
        }
    }
    return;
}


function retrieve_email(username,password,new_val,column,old_email) {
    var email;
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['retrieve_email'],
                      user:    username,
                      pass:    password
                     },
        onSuccess: function (transport) {
            email = transport.responseText;
            if(old_email != email) {
                $('loginWarning').innerHTML = 'Incorrect e-mail provided. Please check your spelling.';
                $('loginWarning').show();
                return;
            } else {
                edit_details_submit(username,password,new_val,column);
            }
        }
    });
}


function edit_details_submit(username,password,new_val,column,email) {  
    new Ajax.Request(LoginScript,{
        method:      'post',
        parameters:  {action: ['edit_details'],
                      user:    username,
                      pass:    password,
                      new_val: new_val,
                      column:  column
                     },
        onSuccess: function (transport) {
            $('loginWarning').innerHTML = transport.responseText;
            if(column == 'pass') {password = new_val;}
            edit_details_confirm(username,password,column);
        }
    });
}


function edit_details_confirm(username,password,column) {
    if ($('loginWarning').innerHTML != "Success") {
        $('loginWarning').show();
    } else {
        CurrentUser = username;
        CurrentPass = password;
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



