function load_login_balloon(event) {
    var html =  '<form id=loginMain method=post action=\'\'>' +

                '<div style=border-bottom-style:solid;border-width:1px;padding-left:3px>' +
                  '<b id=loginTitle>Log in</b></div>' +

                '<table id=loginTable align=center style=font-size:small;padding-top:3px>' +
                  '<tr><td id=loginCreate colspan=2 align=center style=padding-bottom:3px>' +
                    'Don\'t have an account? <a href=# onClick=change_page(\'create\');' +
                      'return false;>Create one</a>.</td></tr>' +

                  '<tr id=loginURow><td align=right>Username:</td>' +
                    '<td><input id=loginUser type=text size=15></td></tr>' +
                  '<tr id=loginERow style=display:none><td align=right>E-mail:</td>' +
                    '<td><input id=loginEmail type=text size=15></td></tr>' +
                  '<tr id=loginPRow><td align=right>Password:</td>' +
                    '<td><input id=loginPass type=password size=15></td></tr>' +
                  '<tr id=loginP2Row style=display:none><td align=right>Retype Password:</td>' +
                    '<td><input id=loginPass2 type=password size=15></td></tr>' +

                  '<tr><td id=loginButtons colspan=2 align=center style=padding-bottom:3px;padding-top:3px>' +
                    '<input id=loginSubmit type=submit value=\'Log in\' />' +
                    '<b id=loginBreak style=display:none>&nbsp; &nbsp;</b>' +
                    '<input id=loginCancel type=button value=\'Cancel\'' +
                      'onClick=change_page(\'main\') style=display:none /></td></tr>' +

                  '<tr id=loginEdit><td colspan=2 align=center><a href=# ' +
                    'onClick=change_page(\'edit\');' +
                      'return false;>Edit account details</a></td></tr>' +

                  '<tr id=loginForgot><td colspan=2 align=center><a href=# ' +
                    'onClick=change_page(\'forgot\');' +
                       'return false;>Forgot my password</a></td></tr>' +
                '</table></form>';

    GBox.showTooltip(event,html,1,250);
}

function change_page(page) {
    switch(page) {
    case 'main':
      $('loginMain').action     = 'change_page(\'create\')';
      $('loginTitle').innerHTML = 'Log in';
      $('loginSubmit').value    = 'Log in';
      $('loginERow').hide();
      $('loginP2Row').hide();
      $('loginBreak').hide();
      break;
    case 'create':
      $('loginMain').action     = 'change_page(\'main\')';
      $('loginTitle').innerHTML = 'Sign up';
      $('loginSubmit').value    = 'Sign up';
      $('loginERow').show();
      $('loginP2Row').show();
      $('loginBreak').show();
      $('loginEmail').size = '15';
      break;
    case 'forgot':
      $('loginMain').action     = 'change_page(\'main\')';
      $('loginTitle').innerHTML = 'Forgot my password';
      $('loginSubmit').value    = 'E-mail my password';
      $('loginERow').show();
      $('loginEmail').size = '18';
      break;
    case 'edit':
      $('loginMain').action     = 'change_page(\'main\')';
      $('loginTitle').innerHTML = 'Edit account details';
      $('loginSubmit').value    = 'Continue';
      $('loginBreak').show();
      break;
    default:
      return;
    }

    if(page == 'main') {
      $('loginEdit').show(); $('loginCancel').hide();
      $('loginCreate').show(); $('loginForgot').show();
    } else {
      $('loginEdit').hide(); $('loginCancel').show();
      $('loginCreate').hide(); $('loginForgot').hide();
    }

    if(page =='forgot') {
      $('loginURow').hide(); $('loginPRow').hide();
    } else {
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

/*function add_user {
  return;
}

function email_user_info {
  return;
}

function confirm_login_info {
  return;
}

function edit_details {
  return;
}*/



