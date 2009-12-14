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

function startAjaxUpload(upload_id) {
  var status       = $(upload_id + '_status');
  var upload_form  = $(upload_id + '_form');
  upload_form.hide();
  var cancel_script = 'Controller.cancel_upload("'+upload_id+'_status","'+upload_id+'");'
  
  status.update("<image src='/gbrowse2/images/spinner.gif' />");
  status.insert(new Element('span').update('<b>Uploading...</b>'));
  status.insert(new Element('a',{   href: 'javascript:void(0)',
                                 onClick: cancel_script
                                }
		            ).update(' Cancel'));

  if (Ajax_Status_Updater == null)
      Ajax_Status_Updater = new Hash();
  var updater = new Ajax.PeriodicalUpdater(
       {success: status.down('span')},
       '#',
       {parameters: {   action: 'upload_status',
                        upload_id: upload_id
                    },
        onSuccess: function(transport) {
	   if (transport.responseText.match(/complete/)) {
	   	    Ajax_Status_Updater.get(upload_id).stop();
	            Controller.update_sections(new Array(userdata_table_id,
							 userimport_table_id,
							 track_listing_id));
	    }
        }
       });
  Ajax_Status_Updater.set(upload_id,updater);
  return true;
}

function completeAjaxUpload(response,upload_id,field_type) {

  var r;

  try {
    r = response.evalJSON(true);
  } catch(e) { r = {success:     false, 
                    upload_name: 'Uploaded file',
                    error_msg:   'The server returned an error during upload'}}

    if (r.success) {

        var fields = field_type == 'upload' ? new Array(track_listing_id,userdata_table_id)
                                            : new Array(track_listing_id,userimport_table_id);
	Controller.add_tracks(r.tracks,
			      function() { 
				  Controller.update_sections(
                                      fields,
				      '',false,false,
                                      function() {
                                          var updater = Ajax_Status_Updater.get(upload_id);
				          if (updater != null)
					  	updater.stop();
                                          $(upload_id).remove();
                                        }
				     )}
				);
    } else {
        if (Ajax_Status_Updater.get(upload_id) !=null)
             Ajax_Status_Updater.get(upload_id).stop();
	Ajax_Status_Updater.unset(upload_id);
        var status = $(upload_id + '_status');
	var uploadName = r.uploadName;
    	var msg =  '<div style="background-color:pink">';
	msg    +=  '<b>'+uploadName+'</b>: '+r.error_msg+'<br>';
	msg    +=  '<a href="javascript:void(0)" onClick="\$\(\''+upload_id+'\').remove()">[Remove Message]</a>';
	msg    +=  '</div>';
    	status.update(msg);
    }
    return true;
}

// NOTE: these functions should be migrated to Controller

function deleteUploadTrack (fileName) {
   var indicator = fileName + "_stat";
   $(indicator).innerHTML = "<image src='/gbrowse2/images/spinner.gif' />";
   new Ajax.Request(document.URL, {
        method:      'post',
        parameters:  {action: 'delete_upload',
	              file:  fileName
		      },
        onSuccess:   function (transport) {
	       var tracks = transport.responseJSON.tracks;
	       if (tracks != null)
		   tracks.each(function(tid) { Controller.delete_track(tid) });
	       Controller.update_sections(new Array(userdata_table_id,userimport_table_id,track_listing_id));
	    }
        }
   );
}

function editUploadData (fileName,sourceFile) {
   editUpload(fileName,sourceFile);
}

function editUploadConf (fileName) {
    editUpload(fileName,'conf');
}

function editUpload (fileName,sourceFile) {
    var editDiv = fileName + "_editfield";
    var editID  = 'edit_' + Math.floor(Math.random() * 99999);
    $(editDiv).innerHTML = '<p><b>Editing '+sourceFile+'</b></p>'
             		  +'<textarea id="'+editID+'" cols="120" rows="20" wrap="off">'
			  + 'fetching...'
                          +'</textarea>'
		          +'<p>'
		          +'<a href="javascript:void(0)" onClick="'
                          +'$(\''+editDiv+'\').innerHTML=\'\'">[Cancel]</a>'
			  +'<button onClick="Controller.uploadUserTrackSource(\''+ editID     +'\','
                                                                            +'\''+ fileName   +'\','
                                                                            +'\''+ sourceFile +'\','
								            +'\''+ editDiv    +'\')">Submit</button>'
			  +'</p>'
                       ;
    Controller.downloadUserTrackSource(editID,fileName,sourceFile);
}

function addAnUploadField(after_element,action,upload_prompt,remove_prompt,field_type,help_link) {

    if (field_type == null) field_type='upload';

    var upload_tag  = 'upload_' + Math.floor(Math.random() * 99999);

    var script      = 'return AIM.submit(this,{onStart:  function() {';
    script         +=                                      'startAjaxUpload(\''+upload_tag+'\')';
    script         +=                                    '},';
    script         +=                         'onComplete: function(response) {'
    script         +=                                      'completeAjaxUpload(response,\''+upload_tag+'\',\''+field_type+'\')';
    script         +=                         '}})';

    var div         = new Element('div',{id:upload_tag});
    var form        = new Element('form',{name: 'ajax_upload',
                                            id: upload_tag + '_form',
                                      onSubmit: script,
				        action: action,
                                       enctype: 'multipart/form-data',
                                        method: 'post'
				      });
    var paragraph   = new Element('p');
    form.update(paragraph);
    paragraph.insert(new Element('a',
    			     {href:  help_link,
			      target:'_new'
			     }).update('<i>[Help with the file format]</i>'));
    paragraph.insert('<br><b>'+upload_prompt+' </b><br>');

    if (field_type=='upload') {
       paragraph.insert(new Element('input',{type:'hidden', 
                                             name:'action', 
                                            value:'upload_file'}));
       paragraph.insert(new Element('input',   {name:'file', id:'upload_field', type:'file'}));
    }

    else if (field_type=='edit') {
       paragraph.insert(new Element('input',{type:'hidden', 
                                             name:'action', 
                                            value:'upload_file'}));
       paragraph.insert(new Element('input',{type:'hidden', 
                                             name:'name', 
                                            value:upload_tag}));
       paragraph.insert(new Element('textarea',{name:'data', id:'edit_field',
       			    		        rows:20, cols:120, wrap:'off'})); 
    }

    else {
       paragraph.insert(new Element('input',{type:'hidden', 
                                             name:'action', 
                                            value:'import_track'}));
       paragraph.insert(new Element('input',   {name:'url',  id:'import_field',type:'text',
                                                size:50}));
    }

    paragraph.insert(new Element('input',{type:'submit', name:'submit', value:'Upload'}));
    paragraph.insert(new Element('input',{type:'hidden', name:'upload_id',value:upload_tag}));
    paragraph.insert(new Element('a',{   href: 'javascript:void(0)',
                                      onClick: 'this.up("div").remove()'
                                 }).update(' '+remove_prompt));
    div.insert(new Element('div',{id:upload_tag+'_status'}));
    div.insert(form);

    var el = $(after_element);
    el.insert({before:div});
}
