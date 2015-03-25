/**
* BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
*
* Copyright (c) 2015 BigBlueButton Inc. and by respective authors (see below).
*
* This program is free software; you can redistribute it and/or modify it under the
* terms of the GNU Lesser General Public License as published by the Free Software
* Foundation; either version 3.0 of the License, or (at your option) any later
* version.
*
* BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
* WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
* PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
*
* You should have received a copy of the GNU Lesser General Public License along
* with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
*
*/
package org.bigbluebutton.main.model.users
{
  import flash.events.TimerEvent;
  import flash.utils.Timer;

  public class AutoReconnect
  {
    public static const LOG:String = "AutoReconnect - ";

    private var _backoff:Number;
    private var _initialBackoff:Number;
    private var _reconnectCallback:Function;
    private var _reconnectParameters:Array;
    private var _retries: Number;

    public function AutoReconnect(initialBackoff:Number = 1000) {
      _initialBackoff = initialBackoff;
      _backoff = initialBackoff;
    }

    public function onDisconnect(callback:Function, ...parameters):void {
      trace(LOG + "onDisconnect, parameters=" + parameters.toString());
      _reconnectCallback = callback;
      _reconnectParameters = parameters;
      attemptReconnect(_initialBackoff);
      _retries = 1;
    }

    public function onConnectionAttemptFailed():void {
      trace(LOG + "onConnectionAttemptFailed");
      attemptReconnect(_backoff);
      _retries = _retries + 1;
    }

    private function attemptReconnect(backoff:Number):void {
      trace(LOG + "attemptReconnect backoff=" + backoff);
      var retryTimer:Timer = new Timer(backoff, 1);
      retryTimer.addEventListener(TimerEvent.TIMER, function():void {
        trace(LOG + "Reconnecting");
        _reconnectCallback.apply(null, _reconnectParameters);
      });
      retryTimer.start();
      if (_backoff < 16000) _backoff = backoff *2;
    }

    public function get Retries():Number {
      return _retries;
    }
  }
}
