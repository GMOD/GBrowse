/** This nice bit of software is used courtesy of the webtoolkit group; the file 
    was renamed to be more informative. **/

/**
*
*  AJAX IFRAME METHOD (AIM)
*  http://www.webtoolkit.info/
*
**/

var Ajax_Status_Updater;
 
AIM = {
 
	frame : function(c) {
 
		var n = 'f' + Math.floor(Math.random() * 99999);
		var d = document.createElement('DIV');
		d.innerHTML = '<iframe style="display:none" src="about:blank" id="'+n+'" name="'+n+'" onload="AIM.loaded(\''+n+'\')"></iframe>';
		document.body.appendChild(d);
 
		var i = document.getElementById(n);
		if (c && typeof(c.onComplete) == 'function') {
			i.onComplete = c.onComplete;
		}
 
		return n;
	},
 
	form : function(f, name) {
		f.setAttribute('target', name);
	},
 
	submit : function(f, c) {
		AIM.form(f, AIM.frame(c));
		if (c && typeof(c.onStart) == 'function') {
			return c.onStart();
		} else {
			return true;
		}
	},
 
	loaded : function(id) {
		var i = document.getElementById(id);
		if (i.contentDocument) {
			var d = i.contentDocument;
		} else if (i.contentWindow) {
			var d = i.contentWindow.document;
		} else {
			var d = window.frames[id].document;
		}
		if (d.location.href == "about:blank") {
			return;
		}
 
		if (typeof(i.onComplete) == 'function') {
			i.onComplete(d.body.innerHTML);
		}
	}
 
}

function startAjaxUpload() {
  $('upload_indicator').innerHTML = "<image src='/gbrowse2/images/buttons/ajax-loader.gif' />";
  $('upload_status').innerHTML = '<b>Uploading...</b>';
  $('ajax_upload').hide();
  if (Ajax_Status_Updater==null)
     Ajax_Status_Updater = new Ajax.PeriodicalUpdater($('upload_status'),'#',{parameters:{new_file_upload_status:1}});
  else
     Ajax_Status_Updater.start();
  return true;
}

function completeAjaxUpload(response) {
      $('upload_status').innerHTML = response;
      $('upload_indicator').innerHTML = '';
      $('ajax_upload').remove();
      if (Ajax_Status_Updater!=null)
         Ajax_Status_Updater.stop();
      Controller.update_sections(new Array(userdata_table_id));
      return true;
}

function deleteUploadTrack (trackName) {
   var indicator = trackName + "_stat";
   $(indicator).innerHTML = "<image src='/gbrowse2/images/buttons/ajax-loader.gif' />";
   new Ajax.Request(document.URL, {
        method:      'post',
        parameters:  {deleteUploadTrack:trackName},
        onSuccess:   function (transport) {
                 Controller.update_sections(new Array(userdata_table_id));
		 }
        }
   );
}




