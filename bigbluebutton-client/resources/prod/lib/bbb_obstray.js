var websocketConnected = false;
var setupStreamUrlOk = true;
var setupStreamPathOk = true;
var setupStreamDisplayOk = true;
var currentMessageCounter = 1;
var requestCallbacks = {};
var bcastUrl = "";
var bcastPath = "";

///funcoes para uso do OBS

function connectOBStray(host, url, path) {
        bcastUrl = url;
        bcastPath = path;
        connectingHost = host;
        
        var url = "ws://" + connectingHost + ":2424";

        
        if (typeof MozWebSocket != "undefined") 
        {
                socket_obsapi = new MozWebSocket(url, "obstraycontrol");
        } 
        else 
        {
                socket_obsapi = new WebSocket(url+"/obstraycontrol/");
        }
        
        try {
                socket_obsapi.onopen = _onWebSocketConnected;
                socket_obsapi.onmessage = _onWebSocketReceiveMessage;
                socket_obsapi.onerror = _onWebSocketError;
                socket_obsapi.onclose = _onWebSocketClose;
        } catch(exception) {
                alert('<p>Error' + exception);  
        }
        return true;
}

function setupDisplay(displayId) {
        var myJSONRequest = {};
        myJSONRequest["type"] = "SetStreamDisplay";
        myJSONRequest["displayid"] = displayId;

        sendMessage(myJSONRequest, setupStreamDisplayCallback);       
        return true; 
}

function setupStreamUrl(url) {
        var myJSONRequest = {};
        myJSONRequest["type"] = "SetStreamUrl";
        myJSONRequest["streamurl"] = url;

        sendMessage(myJSONRequest, setupStreamUrlCallback);       
        return true; 
}

function setupStreamPath(meetingId) {
        var myJSONRequest = {};
        myJSONRequest["type"] = "SetStreamPath";
        myJSONRequest["streampath"] = meetingId;

        sendMessage(myJSONRequest, setupStreamPathCallback);
        return true;        
}

function startStreamingOBS() {
        var myJSONRequest = {};
        myJSONRequest["type"] = "StartStopStreaming";

        if ((setupStreamUrlOk) && (setupStreamPathOk))
                sendMessage(myJSONRequest, startStreamOk);
        else
                alert("Erro configuração parâmetros do servidor!");
}

function stopOBS() {
        var myJSONRequest = {};
        myJSONRequest["type"] = "StartStopStreaming";

        sendMessage(myJSONRequest, stopStreamOk)  

}

function setupStreamUrlCallback(resp) {
        var reqOk = resp["status"];
        setupStreamUrlOk = true;
}

function setupStreamPathCallback(resp) {
        var reqOk = resp["status"];
        setupStreamPathOk = true;
}

function setupStreamDisplayCallback(resp) {
        var reqOk = resp["status"];
        setupStreamDisplayOk = true;
}

function startStreamOk(resp)
{
        var reqOk = resp["status"];
}

function stopStreamOk(resp)
{
        var reqOk = resp["status"];
}

function _onWebSocketConnected()
{
        websocketConnected = true;
        
        /* store successfully connected host for future */
        //setOBSHost(connectingHost);
        
        /* call the generic onWebSocketConnected function */
        //onWebSocketConnected();
        setupStreamUrl(bcastUrl);
        setupStreamPath(bcastPath);
        setupDisplay(1);
        startStreamingOBS();
}

function _onWebSocketReceiveMessage(msg)
{
        var response = JSON.parse(msg.data);
        if(!response)
        {
                return;
        }
        var id = response["messageid"];
                
        if(response["status"] == "error")
        {
                console.log("Error: " + response["error"]);
        }
                
        var callback = requestCallbacks[id];
        if(callback)
        {
                callback(response);
                requestCallbacks[id] = null;
        }
}

function _onWebSocketError(err)
{
        console.log("websocket error");
        socket_obsapi.close();
}

function gracefulWebsocketClose()
{        
        if(socket_obsapi)
        {
                socket_obsapi.onopen = null;
                socket_obsapi.onmessage = null;
                socket_obsapi.onerror = null;
                socket_obsapi.onclose = null;
                
                socket_obsapi.close();
        }
        
        _onWebSocketClose("Closed gracefully.");
}

function _onWebSocketClose(err)
{
        console.log("websocket close");
        
        websocketConnected = false;
        //onWebSocketClose(); calls socket_obsapi socket closed (fechou)
}

function getNextID()
{
        currentMessageCounter++;
        return currentMessageCounter + "";
}

function sendMessage(msg, callback)
{
        if(websocketConnected)
        {
                var id =  getNextID();
                if(!callback)
                {
                        requestCallbacks[id] = function(){};
                }
                else
                {
                        requestCallbacks[id] = callback;
                }
                msg["messageid"] = id;
                
                var serializedMessage = JSON.stringify(msg);
                socket_obsapi.send(serializedMessage);
        }
}