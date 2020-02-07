{-
    TODO What is this about?

        //  if we don't explicitly set this field, h2o will send with
        //  transfer-encoding: chunked
        //
        if ( 1 == has_len_i ) {
          rec_u->res.content_length = ( 0 == gen_u->bod_u ) ?
                                      0 : gen_u->bod_u->len_w;
        }

    TODO Does this matter, is is using WAI's default behavior ok?

        rec_u->res.reason = (status < 200) ? "weird" :
                            (status < 300) ? "ok" :
                            (status < 400) ? "moved" :
                            (status < 500) ? "missing" :
                            "hosed";

    TODO This uses `W.openFreePort` to find a free port, but I actually
         want to mimick the old kings behavior and try 8080, then 8081,
         etc. I think I'll have to reimplement a varianet of
         `openFreePort` myself, but this will work for now.
-}

module Vere.Http.Server where

import Arvo            hiding (ServerId, reqBody, reqUrl, secure)
import Config
import Data.Conduit
import Noun
import UrbitPrelude    hiding (Builder)
import Vere.Pier.Types

import Data.Binary.Builder (Builder, fromByteString)
import Data.Bits           (shiftL, (.|.))
import Network.Socket      (SockAddr(..))
import System.Directory    (doesFileExist, removeFile)
import System.Random       (randomIO)
import Vere.Http           (convertHeaders, unconvertHeaders)

import qualified Network.HTTP.Types          as H
import qualified Network.Wai                 as W
import qualified Network.Wai.Conduit         as W
import qualified Network.Wai.Handler.Warp    as W
import qualified Network.Wai.Handler.WarpTLS as W


-- Internal Types --------------------------------------------------------------

type ReqId = Atom
type SeqId = UD -- Unused, always 1

{-
    The sequence of actions on a given request *should* be:

        [%head .] [%bloc .]* %done

    But we will actually accept anything, and mostly do the right
    thing. There are two situations where we ignore ignore the data from
    some actions.

    - If you send something *after* a %done action, it will be ignored.
    - If you send a %done before a %head, we will produce "444 No
      Response" with an empty response body.
-}
data RespAction
    = RAHead ResponseHeader File
    | RAFull ResponseHeader File
    | RABloc File
    | RADone
  deriving (Eq, Ord, Show)

data LiveReqs = LiveReqs
    { nextReqId  :: ReqId
    , activeReqs :: Map ReqId (TQueue RespAction)
    }

data Ports = Ports
    { pHttps :: Maybe Port
    , pHttp  :: Port
    , pLoop  :: Port
    }
  deriving (Eq, Ord, Show)

newtype Drv = Drv { unDrv :: MVar (Maybe Serv) }

data Serv = Serv
    { sServId    :: ServId
    , sConfig    :: HttpServerConf
    , sLoopTid   :: Async ()
    , sHttpTid   :: Async ()
    , sHttpsTid  :: Maybe (Async ())
    , sPorts     :: Ports
    , sPortsFile :: FilePath
    , sLiveReqs  :: TVar LiveReqs
    }


-- RespAction -- Reorganized HttpEvent for Cleaner Processing ------------------

reorgHttpEvent :: HttpEvent -> [RespAction]
reorgHttpEvent = \case
    Start head mBlk True   -> [RAFull head (fromMaybe "" mBlk)]
    Start head mBlk False  -> [RAHead head (fromMaybe "" mBlk)]
    Cancel ()              -> [RADone]
    Continue mBlk isDone   -> toList (RABloc <$> mBlk)
                           <> if isDone then [RADone] else []


-- Generic Service Stop/Restart -- Using an MVar for Atomicity -----------------

{-
    Restart a running service.

    This can probably be made simpler, but it

    - Sets the MVar to Nothing if there was an exception whil starting
      or stopping the service.

    - Keeps the MVar lock until the restart process finishes.
-}
restartService :: ∀e s. HasLogFunc e
               => MVar (Maybe s)
               -> RIO e s
               -> (s -> RIO e ())
               -> RIO e (Either SomeException s)
restartService vServ sstart kkill = do
    logDebug "restartService"
    modifyMVar vServ $ \case
        Nothing -> doStart
        Just sv -> doRestart sv
  where
    doRestart :: s -> RIO e (Maybe s, Either SomeException s)
    doRestart serv = do
        logDebug "doStart"
        try (kkill serv) >>= \case
            Left exn -> pure (Nothing, Left exn)
            Right () -> doStart

    doStart :: RIO e (Maybe s, Either SomeException s)
    doStart = do
        logDebug "doStart"
        try sstart <&> \case
            Right s  -> (Just s,  Right s)
            Left exn -> (Nothing, Left exn)

stopService :: HasLogFunc e
            => MVar (Maybe s)
            -> (s -> RIO e ())
            -> RIO e (Either SomeException ())
stopService vServ kkill = do
    logDebug "stopService"
    modifyMVar vServ $ \case
        Nothing -> pure (Nothing, Right ())
        Just sv -> do res <- try (kkill sv)
                      pure (Nothing, res)


-- Live Requests Table -- All Requests Still Waiting for Responses -------------

emptyLiveReqs :: LiveReqs
emptyLiveReqs = LiveReqs 1 mempty

respondToLiveReq :: TVar LiveReqs -> ReqId -> RespAction -> STM ()
respondToLiveReq var req ev = do
    mVar <- lookup req . activeReqs <$> readTVar var
    case mVar of
        Nothing -> pure ()
        Just tv -> writeTQueue tv ev

rmLiveReq :: TVar LiveReqs -> ReqId -> STM ()
rmLiveReq var reqId = do
    liv <- readTVar var
    writeTVar var (liv { activeReqs = deleteMap reqId (activeReqs liv) })

newLiveReq :: TVar LiveReqs -> STM (ReqId, TQueue RespAction)
newLiveReq var = do
    liv <- readTVar var
    tmv <- newTQueue

    let (nex, act) = (nextReqId liv, activeReqs liv)

    writeTVar var (LiveReqs (nex+1) (insertMap nex tmv act))

    pure (nex, tmv)


-- Ports File ------------------------------------------------------------------

removePortsFile :: FilePath -> RIO e ()
removePortsFile pax =
    io (doesFileExist pax) >>= \case
        True  -> io $ removeFile pax
        False -> pure ()

portsFileText :: Ports -> Text
portsFileText Ports{..} =
  unlines $ catMaybes
    [ pHttps <&> \p -> (tshow p <> " secure public")
    , Just (tshow (unPort pHttp) <> " insecure public")
    , Just (tshow (unPort pLoop) <> " insecure loopback")
    ]

writePortsFile :: FilePath -> Ports -> RIO e ()
writePortsFile f = writeFile f . encodeUtf8 . portsFileText


-- Random Helpers --------------------------------------------------------------

cordBytes :: Cord -> ByteString
cordBytes = encodeUtf8 . unCord

pass :: Monad m => m ()
pass = pure ()

whenJust :: Monad m => Maybe a -> (a -> m ()) -> m ()
whenJust Nothing  act = pure ()
whenJust (Just a) act = act a

cookMeth :: W.Request -> Maybe Method
cookMeth = H.parseMethod . W.requestMethod >>> \case
             Left _  -> Nothing
             Right m -> Just m

reqIdCord :: ReqId -> Cord
reqIdCord = Cord . tshow

reqBody :: W.Request -> RIO e (Maybe File)
reqBody req = do
    bodyLbs <- io $ W.strictRequestBody req
    pure $ if length bodyLbs == 0
      then Nothing
      else Just $ File $ Octs (toStrict bodyLbs)

reqAddr :: W.Request -> Address
reqAddr = W.remoteHost >>> \case
    SockAddrInet  _ a     -> AIpv4 (Ipv4 a)
    SockAddrInet6 _ _ a _ -> AIpv6 (mkIpv6 a)
    _                     -> error "invalid sock addr"

mkIpv6 :: (Word32, Word32, Word32, Word32) -> Ipv6
mkIpv6 (p, q, r, s) = Ipv6 (pBits .|. qBits .|. rBits .|. sBits)
  where
    pBits = shiftL (fromIntegral p) 0
    qBits = shiftL (fromIntegral q) 32
    rBits = shiftL (fromIntegral r) 64
    sBits = shiftL (fromIntegral s) 96

reqUrl :: W.Request -> Cord
reqUrl r = Cord $ decodeUtf8 $ W.rawPathInfo r <> W.rawQueryString r


-- Utilities for Constructing Events -------------------------------------------

data WhichServer = Secure | Insecure | Loopback
  deriving (Eq)

servEv :: HttpServerEv -> Ev
servEv = EvBlip . BlipEvHttpServer

bornEv :: KingId -> Ev
bornEv king =
    servEv $ HttpServerEvBorn (king, ()) ()

liveEv :: ServId -> Ports -> Ev
liveEv sId Ports{..} =
    servEv $ HttpServerEvLive (sId, ()) pHttp pHttps

cancelEv :: ServId -> ReqId -> Ev
cancelEv sId reqId =
    servEv $ HttpServerEvCancelRequest (sId, reqId, 1, ()) ()

reqEv :: ServId -> ReqId -> WhichServer -> Address -> HttpRequest -> Ev
reqEv sId reqId which addr req =
    case which of
        Loopback ->
            servEv $ HttpServerEvRequestLocal (sId, reqId, 1, ())
                   $ HttpServerReq False addr req
        _        ->
            servEv $ HttpServerEvRequest (sId, reqId, 1, ())
                   $ HttpServerReq (which == Secure) addr req



-- Http Server Flows -----------------------------------------------------------

data Req
    = RHead ResponseHeader [File]
    | RFull ResponseHeader [File]
    | RNone

{-
    This accepts all action orderings so that there are no edge-cases
    to be handled:

    - If %bloc before %head, collect it and wait for %head.
    - If %done before %head, ignore all chunks and produce Nothing.
-}
getReq :: TQueue RespAction -> RIO e Req
getReq tmv = go []
  where
    go çunks = atomically (readTQueue tmv) >>= \case
                 RAHead head ç -> pure $ RHead head $ reverse (ç : çunks)
                 RAFull head ç -> pure $ RFull head $ reverse (ç : çunks)
                 RABloc ç      -> go (ç : çunks)
                 RADone        -> pure RNone

{-
    - Immediatly yield all of the initial chunks
    - Yield the data from %bloc action.
    - Close the stream when we hit a %done action.
-}
streamBlocks :: HasLogFunc e
             => e -> [File] -> TQueue RespAction
             -> ConduitT () (Flush Builder) IO ()
streamBlocks env init tmv =
    for_ init yieldÇunk >> go
  where
    yieldFlush = \x -> yield (Chunk x) >> yield Flush
    logDupHead = runRIO env
               $ logError "Multiple %head actions on one request"

    yieldÇunk  = \case
      "" -> pure ()
      c  -> (yieldFlush . fromByteString . unOcts . unFile) c

    go = atomically (readTQueue tmv) >>= \case
           RAHead head c -> logDupHead >> yieldÇunk c >> go
           RAFull head c -> logDupHead >> yieldÇunk c >> go
           RABloc c      -> yieldÇunk c
           RADone        -> pure ()

sendResponse :: HasLogFunc e
             => (W.Response -> IO W.ResponseReceived)
             -> TQueue RespAction
             -> RIO e W.ResponseReceived
sendResponse cb tmv = do
    env <- ask
    getReq tmv >>= \case
        RNone     -> io $ cb $ W.responseLBS (H.mkStatus 444 "No Response") []
                             $ ""
        RFull h f -> io $ cb $ W.responseLBS (hdrStatus h) (hdrHeaders h)
                             $ fromStrict $ concat $ unOcts . unFile <$> f
        RHead h i -> io $ cb $ W.responseSource (hdrStatus h) (hdrHeaders h)
                             $ streamBlocks env i tmv
  where
    hdrHeaders :: ResponseHeader -> [H.Header]
    hdrHeaders = unconvertHeaders . headers

    hdrStatus :: ResponseHeader -> H.Status
    hdrStatus = toEnum . fromIntegral . statusCode

liveReq :: TVar LiveReqs -> RAcquire e (ReqId, TQueue RespAction)
liveReq vLiv = mkRAcquire ins del
  where
    ins = atomically (newLiveReq vLiv)
    del = atomically . rmLiveReq vLiv . fst

app :: HasLogFunc e
    => e -> ServId -> TVar LiveReqs -> (Ev -> STM ()) -> WhichServer
    -> W.Application
app env sId liv plan which req respond =
   runRIO env $
   rwith (liveReq liv) $ \(reqId, respVar) -> do
        body <- reqBody req
        meth <- maybe (error "bad method") pure (cookMeth req)

        let addr  = reqAddr req
            hdrs  = convertHeaders $ W.requestHeaders req
            evReq = HttpRequest meth (reqUrl req) hdrs body

        atomically $ plan (reqEv sId reqId which addr evReq)

        try (sendResponse respond respVar) >>= \case
          Right rr -> pure rr
          Left exn -> do
            io $ atomically $ plan (cancelEv sId reqId)
            logError $ display ("Exception during request" <> tshow exn)
            throwIO (exn :: SomeException)


-- Top-Level Driver Interface --------------------------------------------------

{-
    TODO Need to find an open port.
-}
startServ :: (HasPierConfig e, HasLogFunc e)
          => HttpServerConf -> (Ev -> STM ())
          -> RIO e Serv
startServ conf plan = do
  logDebug "startServ"

  let tls = hscSecure conf <&> \(PEM key, PEM cert) ->
              (W.tlsSettingsMemory (cordBytes cert) (cordBytes key))

  sId <- io $ ServId . UV . fromIntegral <$> (randomIO :: IO Word32)
  liv <- newTVarIO emptyLiveReqs

  (httpPortInt,  httpSock)  <- io $ W.openFreePort -- 8080  -- 80 if real ship
  (httpsPortInt, httpsSock) <- io $ W.openFreePort -- 8443  -- 443 if real ship
  (loopPortInt,  loopSock)  <- io $ W.openFreePort -- 12321 -- ??? if real ship

  let httpPort  = Port (fromIntegral httpPortInt)
      httpsPort = Port (fromIntegral httpsPortInt)
      loopPort  = Port (fromIntegral loopPortInt)

  let loopOpts  = W.defaultSettings & W.setPort (fromIntegral loopPort)
                                    & W.setHost "127.0.0.1"
                                    & W.setTimeout (5 * 60)
      httpOpts  = W.defaultSettings & W.setPort (fromIntegral httpPort)
      httpsOpts = W.defaultSettings & W.setPort (fromIntegral httpsPort)

  env <- ask

  logDebug "Starting loopback server"
  loopTid  <- async $ io
                    $ W.runSettingsSocket loopOpts loopSock
                    $ app env sId liv plan Loopback

  logDebug "Starting HTTP server"
  httpTid  <- async $ io
                    $ W.runSettingsSocket httpOpts httpSock
                    $ app env sId liv plan Insecure

  logDebug "Starting HTTPS server"
  httpsTid <- for tls $ \tlsOpts ->
                async $ io
                      $ W.runTLSSocket tlsOpts httpsOpts httpsSock
                      $ app env sId liv plan Secure

  pierPath <- view pierPathL
  let por = Ports (tls <&> const httpsPort) httpPort loopPort
      fil = pierPath <> "/.http.ports"

  logDebug $ displayShow (sId, por, fil)

  logDebug "Finished started HTTP Servers"

  pure $ Serv sId conf loopTid httpTid httpsTid por fil liv

killServ :: HasLogFunc e => Serv -> RIO e ()
killServ Serv{..} = do
    cancel sLoopTid
    cancel sHttpTid
    traverse_ cancel sHttpsTid
    removePortsFile sPortsFile
    (void . waitCatch) sLoopTid
    (void . waitCatch) sHttpTid
    traverse_ (void . waitCatch) sHttpsTid

kill :: HasLogFunc e => Drv -> RIO e ()
kill (Drv v) = stopService v killServ >>= fromEither

respond :: HasLogFunc e
        => Drv -> ReqId -> HttpEvent -> RIO e ()
respond (Drv v) reqId ev = do
    readMVar v >>= \case
        Nothing -> pure ()
        Just sv -> do logDebug $ displayShow $ reorgHttpEvent ev
                      for_ (reorgHttpEvent ev) $
                        atomically . respondToLiveReq (sLiveReqs sv) reqId

serv :: ∀e. (HasPierConfig e, HasLogFunc e)
     => KingId -> QueueEv
     -> ([Ev], RAcquire e (EffCb e HttpServerEf))
serv king plan =
    (initialEvents, runHttpServer)
  where
    initialEvents :: [Ev]
    initialEvents = [bornEv king]

    runHttpServer :: RAcquire e (EffCb e HttpServerEf)
    runHttpServer = handleEf <$> mkRAcquire (Drv <$> newMVar Nothing) kill

    restart :: Drv -> HttpServerConf -> RIO e Serv
    restart (Drv var) conf = do
        logDebug "Restarting http server"
        res <- fromEither =<< restartService var (startServ conf plan) killServ
        logDebug "Done restating http server"
        pure res

    handleEf :: Drv -> HttpServerEf -> RIO e ()
    handleEf drv = \case
        HSESetConfig (i, ()) conf -> do
            -- print (i, king)
            -- when (i == fromIntegral king) $ do
                logDebug "restarting"
                Serv{..} <- restart drv conf
                logDebug "Enqueue %live"
                atomically $ plan (liveEv sServId sPorts)
                logDebug "Write ports file"
                writePortsFile sPortsFile sPorts
        HSEResponse (i, req, _seq, ()) ev -> do
            -- print (i, king)
            -- when (i == fromIntegral king) $ do
                logDebug "respond"
                respond drv (fromIntegral req) ev
