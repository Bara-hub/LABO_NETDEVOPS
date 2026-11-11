try {
  var params = JSON.parse(value);
  if (params.event_value !== '1') {
    return 'ignoré : événement de résolution';
  }
  var req = new HttpRequest();
  req.addHeader('Content-Type: application/x-www-form-urlencoded');
  var body = 'token=' + encodeURIComponent(params.trigger_token) +
             '&ref=' + encodeURIComponent(params.ref) +
             '&' + encodeURIComponent('variables[ROLLBACK]') + '=true';
  var url = params.gitlab_url + '/api/v4/projects/' + params.project_id + '/trigger/pipeline';
  var resp = req.post(url, body);
  if (req.getStatus() !== 201) {
    throw 'GitLab a répondu ' + req.getStatus() + ' : ' + resp;
  }
  return 'pipeline lancé : ' + resp;
}
catch (error) {
  Zabbix.log(3, 'gitlab-rollback : ' + error);
  throw 'Echec du webhook : ' + error;
}