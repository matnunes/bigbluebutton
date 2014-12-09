/**
* BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
* 
* Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
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
package org.bigbluebutton.deskshare.server.red5

import org.red5.server.api.{IContext, IClient, IConnection}
import org.red5.server.api.Red5
import org.red5.server.api.stream.IBroadcastStream
import org.red5.server.api.stream.IStream
import org.red5.server.so.SharedObjectService
import org.red5.server.api.so.{ISharedObject, ISharedObjectService}
import org.red5.server.stream.IProviderService
import org.bigbluebutton.deskshare.server.ScreenVideoBroadcastStream
import org.bigbluebutton.deskshare.server.RtmpClientAdapter
import org.bigbluebutton.deskshare.server.stream._
import org.bigbluebutton.deskshare.server.socket.DeskShareServer
import org.bigbluebutton.deskshare.server.MultiThreadedAppAdapter
import scala.actors.Actor
import scala.actors.Actor._
import net.lag.configgy.Configgy
import net.lag.logging.Logger
import java.io.File
import java.util.ArrayList
import java.util.concurrent.CountDownLatch
import java.util.Set
import org.red5.server.api.scope.{IScope}
import org.red5.server.util.ScopeUtils

class DeskshareApplication(streamManager: StreamManager, deskShareServer: DeskShareServer) extends MultiThreadedAppAdapter {
	private val deathSwitch = new CountDownLatch(1)

	// load our config file and configure logfiles.
	Configgy.configure("webapps/deskshare/WEB-INF/deskshare.conf")
 
	private val logger = Logger.get 
	var appScope: IScope = null
	var myStream: IBroadcastStream = null
	var rtmpCA: RtmpClientAdapter = null
	var myDeskShareStream: DeskshareStream = null
	var svBroadcastStream: ScreenVideoBroadcastStream = null
 
	override def appStart(app: IScope): Boolean = {
		logger.debug("deskShare appStart");
		logger.debug("-----DeskshareApplication")
		appScope = app
		super.setScope(appScope)
		if (appScope == null) println ("APSCOPE IS NULL!!!!")
		else println("APPSCOPE is NOT NULL!!!!")
  
		// make sure there's always one actor running so scala 2.7.2 doesn't kill off the actors library.
		actor {
			deathSwitch.await
		}
    
		streamManager.setDeskshareApplication(this)
		deskShareServer.start();
		super.appStart(app)
	}
	
	override def appConnect(conn: IConnection, params: Array[Object]): Boolean = {
		logger.debug("deskShare appConnect to scope " + conn.getScope().getContextPath());
		super.appConnect(conn, params);
	}
	
	override def appDisconnect(conn: IConnection) {
		logger.info("DeskshareApplication appDisconnect");
		super.appDisconnect(conn);
	}
	
	override def appStop(app: IScope) {
		logger.info("Stopping DeskshareApplication")
		deskShareServer.stop();
		super.appStop(app)
	}
 
	def getApplicationScope(): IScope = {
		if (appScope == null) println ("getAppScope: APSCOPE IS NULL!!!!")
		else println("getAppScope: APPSCOPE is NOT NULL!!!!")
		appScope;
	}
 
	def getAppSharedObject(): ISharedObject = {
		if (appScope == null) println ("getAppSharedObject: APSCOPE IS NULL!!!!")
		else println("getAppSharedObject: APPSCOPE is NOT NULL!!!!")
	    return getSharedObject(appScope, "deskSO")
	}
 
	private def getRoomScope(room:String):Option[IScope] = {
		if (appScope == null) {
		  logger.error("Cannot find room scope %s because app scope is null", room)
		  return None
		}
  
		var roomScope:IScope  = ScopeUtils.resolveScope(appScope, room)
	   
		if (roomScope == null) {
			if (appScope.createChildScope(room)) {
				logger.debug("DeskshareApplication: RoomScope for [ %s ] created", room)
				
				roomScope = ScopeUtils.resolveScope(appScope, room)
				
				if (roomScope == null) {
				  logger.error("DeskshareApplication: ****!!!!!!! ROOM SCOPE IS NULL!!!!!!*")
				  println("DeskshareApplication: ****!!!!!!! ROOM SCOPE IS NULL!!!!!!*")
				}
			} else {
				logger.error("DeskshareApplication: Failed to create scope for room [ %s ]", room)
				return None
			}
		} else {
				logger.debug("DeskshareApplication: Room scope [ %s ] was found", room)
		}
    	return Some(roomScope)
	}
 
	private def getRoomSharedObject(roomScope:IScope, name:String):Option[ISharedObject] = {
	    var soName:String = name + "-deskSO";
	  
		if (roomScope == null) {
		   logger.error("DeskshareApplication: Cannot get shared object because room scope is null.")
		   return None
		} 
		logger.debug("DeskshareApplication: Getting shared object.")
		var deskSO:ISharedObject = getSharedObject(roomScope, soName)
		logger.debug("DeskshareApplication: Got shared object.")
		
		if (deskSO == null) {	
		  logger.debug("DeskshareApplication: Creating shared object.")
			if (createSharedObject(roomScope, soName, false)) {
			  logger.debug("DeskshareApplication: Created shared object. Getting shared object.")
			  deskSO = getSharedObject(roomScope, soName)
			} else {
			  logger.error("DeskshareApplication: Failed to create shared object for room")
			//	println ("Failed to create shared object")
				return None
			}
		} else {
		  logger.debug("DeskshareApplication: Not creating shared object as one has already been created.")
		}
		return Some(deskSO)
	}
 
 	def createDeskshareClient(name: String): Option[RtmpClientAdapter] = {
 //		getRoomScope(name) match {
//	     case None => logger.error("DeskshareApplication: Failed to get room scope for [ %s ] ", name)
//	     case Some(roomScope) => {
	    	 getRoomSharedObject(appScope, name) match {
	    	   case None => logger.error("DeskshareApplication:: Failed to get shared object for room [ %s ]",name)
	    	   case Some(deskSO) => {
	    	     logger.debug("DeskshareApplication: Creating RtmpClientAdapter")
	    		 return Some(new RtmpClientAdapter(deskSO))
	    	   }
//	    	 }
//	       }
	   }
	   
	   return None
 	
 	}
 	
	def createScreenVideoBroadcastStream(name: String): Option[ScreenVideoBroadcastStream] = {
	  logger.info("DeskshareApplication: Creating ScreenVideoBroadcastStream")
//	   getRoomScope(name) match {
//	     case None => logger.error("Failed to get room scope %s", name)
//	     case Some(roomScope) => {
	    	 getRoomSharedObject(appScope, name) match {
	    	   case None => logger.error("Failed to get shared object for room %s",name)
	    	   case Some(deskSO) => {
	    	     logger.info("DeskshareApplication: Creating Broadcast Stream for room [ %s ]", name)
				 logger.info("-----DeskshareApplication: streamManager.createOBSStream [ %s ]", name)
	    		   return createBroadcastStream(name, appScope)
	    	   }
	    	 }
//	       }
//	   }
	   
	   return None	   
	}
 
	private def createBroadcastStream(name:String, roomScope:IScope):Option[ScreenVideoBroadcastStream] = {
		if (name == null || roomScope == null) {
		   logger.error("Cannot create broadcast stream. Invalid parameter")
		   return None
		}
  
		logger.debug("DeskshareApplication: Creating ScreenVideoBroadcastStream for room [ %s ]", name)
		var broadcastStream = new ScreenVideoBroadcastStream(name)
		broadcastStream.setPublishedName(name)
		broadcastStream.setScope(roomScope)
    
		val context: IContext  = roomScope.getContext()
		
		logger.debug("DeskshareApplication: Getting provider service for room [ %s ]", name)		
		val providerService: IProviderService  = context.getBean(IProviderService.BEAN_NAME).asInstanceOf[IProviderService]
		
		logger.debug("DeskshareApplication: Registering broadcast stream for room [ %s ]", name)
		if (providerService.registerBroadcastStream(roomScope, name, broadcastStream)) {
			// Do nothing. Successfully registered a live broadcast stream. (ralam Sept. 4, 2012)
		} else{
			logger.error("DeskShareStream: Could not register broadcast stream")
		}
    
	   return Some(broadcastStream)
	}

	// override def streamBroadcastStart(stream:IBroadcastStream) {
	// 	var rScope:IScope  = ScopeUtils.resolveScope(appScope, stream.getPublishedName())
	// 	var pubName:String = stream.getPublishedName() 

	// 	myStream = stream

	//     //recebeu uma stream
	//     logger.info("==============> new stream being published [ %s ]", pubName)

	// 	//super.streamBroadcastStart(stream)
	// 	//createBroadcastStream(pubName, appScope)
	// 	streamManager.createStream(pubName, 800, 600)
	// 	createDeskshareClient(pubName) match {
	//     	   case None => logger.info("========> DeskshareApplication streamBroadcastStart:: Failed to get shared object for room")
	//     	   case Some(rtmpAdp) => {
	//     	     rtmpCA = rtmpAdp
	//     	     rtmpCA.sendDeskshareStreamStarted(800,600)
	//     	   }
	//     	}
 //    }

	override def streamBroadcastStart(stream:IBroadcastStream) {
		super.streamBroadcastStart(stream)
		var rScope:IScope  = ScopeUtils.resolveScope(appScope, stream.getPublishedName())
		var pubName:String = stream.getPublishedName() 

		createBroadcastStream(pubName, appScope) match {
			case  Some(svb) => svBroadcastStream = svb
			case None => logger.info("========> DeskshareApplication createBroadcastStream: Failed to createStream [%s]", pubName)
		}

		streamManager.createStream(pubName, 960, 540) match {
    			case Some(dStream) => myDeskShareStream = dStream
    			case None => logger.info("========> DeskshareApplication streamBroadcastStart:: Failed to createStream [%s]", pubName)
		}

		myDeskShareStream ! StartStream
		myStream = stream
		//streamPublishStart(stream)

		// getRoomScope(pubName) match {
		//      case None => logger.info("DeskshareApplication: Failed to get room scope for stopIStream([ %s ]) ", pubName)
		//      case Some(roomScope) => {
		//      		// roomScope.getClientBroadcastStream(pubName).stop()
	 //    			appScope.getBroadcastScope(pubName).getClientBroadcastStream().close()	
	 //    			logger.info("-=======> DeskshareApplication: Sent close([ %s ]) ", pubName)
		//      	}
	 //    	}

	    //recebeu uma stream
	    logger.info("==============> new stream being published [ %s ]", pubName)

		// createBroadcastStream(pubName, appScope) createBroadcasStream chamado no DeskshareStream

		// createDeskshareClient(pubName) match {
	 //    	   case None => logger.info("========> DeskshareApplication streamBroadcastStart:: Failed to get shared object for room")
	 //    	   case Some(rtmpAdp) => {
	 //    	     rtmpCA = rtmpAdp
	 //    	     rtmpCA.sendDeskshareStreamStarted(800,600)
	 //    	   }
	 //    	}
    }

	    //stops a broadcasted stream on demand
	  //   def stopIStream(room:String) {
	  //   	logger.info("==============> stream being STOPPED! [ %s ]", room)
	  //   	rtmpCA.sendDeskshareStreamStopped(new ArrayList[Object]())
		 //   	var rScope:IScope  = appScope
			// // val context: IContext  = rScope.getContext()

	  // //   	logger.info("DeskshareApplication stopIStream: Getting provider service for room [ %s ]", room)		
			// // val providerService: IProviderService  = context.getBean(IProviderService.BEAN_NAME).asInstanceOf[IProviderService]
			
			// // logger.info("DeskshareApplication stopIStream: UnRegistering broadcast stream for room [ %s ]", room)
			// // if (providerService.unregisterBroadcastStream(rScope, room)) {
			// // 	// Do nothing. Successfully registered a live broadcast stream. (ralam Sept. 4, 2012)
			// // 	logger.info("DeskShareStream stopIStream: Unregister broadcast stream successfully")
			// // } else{
			// // 	logger.info("DeskShareStream stopIStream: Could not unregister broadcast stream")
			// // }

	  //   	//(problemas de erros de desconexão) >>
	  //   	// getRoomScope(room) match {
		 //    //  case None => logger.error("DeskshareApplication: Failed to get room scope for stopIStream([ %s ]) ", room)
		 //    //  case Some(roomScope) => {
		 //    //  		roomScope.getClientBroadcastStream(room).stop()
	  //   	// 		roomScope.getClientBroadcastStream(room).close()
		 //    //  	}
	  //   	// }
	  //   	// <<
	  //   	// myStream.stop()
			// myStream.close()
	  //   	deskShareServer.stop();
			// super.appStop(appScope)
	    	

	  //   	// //getClients
	  //   	// var clientes:Set[IClient] = rScope.getClients()
	  //   	// for (cliente <- List(clientes))
	  //   	// { var a:IClient = cliente.asInstanceOf[IClient]
	  //   	// 	a.disconnect()
	  //   	// 	logger.info("==============> client killed")
	  //   	// }

			// //getConnections
	  //   	// var connections:Set[IConnection] = rScope.getClientConnections()
	  //   	// for (cone <- List(connections))
	  //   	// { var a:IConnection = cone.asInstanceOf[IConnection]
	  //   	// 	appDisconnect(a);
	  //   	// 	// a.close()
	  //   	// 	logger.info("==============> client killed")
	  //   	// }

	  //   	// connections.appDisconnect()
			// // conns = rScope.getClientConnections()
	  // //   	val setConn:Set[IConnection] = rScope.getClientConnections()
			// // for ( iConnection <- setConn) {
			// // 		iConnection.close()
			// // }
	  //   	// var conn:IConnection = Red5.getConnectionLocal();
	  //   	// var clien:IClient = conn.getClient();
	  //   	// clien.disconnect();
	  //   	//IStreamCapableConnection
	  //   	// conn.close()
	  //   }

  	def stopIStream(room:String) {
		var conn:IConnection = Red5.getConnectionLocal()
		myDeskShareStream ! StopStream		    	
		deskShareServer.stop()
		disconnect(conn, appScope)
		streamBroadcastClose(getBroadcastStream(appScope,room))
	    // logger.info("-=======> DeskshareApplication: Sent close([ %s ]) ", room)

		// rtmpCA.sendDeskshareStreamStopped(new ArrayList[Object]())

		// streamManager ! RemoveStream(room)
		// super.appStop(appScope);

	}
    
    //método chamado quando o app é parado (não quando faz o close)
    override def streamBroadcastClose(stream:IBroadcastStream) {
    	
    	var pubName:String = stream.getPublishedName() 
		logger.info("==============> stream being closed [ %s ]", pubName)
  //   	streamManager.stopyStream(pubName)
     	// streamManager.destroyStream(pubName)

  //   	deskShareServer.stop();
		// super.appStop(appScope)

		// var conn:IConnection = Red5.getConnectionLocal();
  //       var scopeName:String = "";
  //       if (conn != null) {
  // 	       scopeName = conn.getScope().getName();
  //       } else {
  // 	       log.info("Connection local was null, using scope name from the stream: {}", stream);
  // 	       scopeName = stream.getScope().getName();
  //       }
  		super.streamBroadcastClose(stream)
	}

}
