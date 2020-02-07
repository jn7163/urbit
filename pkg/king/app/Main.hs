{-
    # Booting a Ship

    - TODO Don't just boot, also run the ship (unless `-x` is set).

    # Event Pruning

    - `king discard-events NUM_EVENTS`: Delete the last `n` events from
      the event log.

    - `king discard-events-interactive`: Iterate through the events in
      the event log, from last to first, pretty-print each event, and
      ask if it should be pruned.

    # `-N` -- Dry Run

    Disable all persistence and use no-op networking.

    # Implement subcommands to test event and effect parsing.

    - `king * --collect-fx`: All effects that come from the serf get
      written into the `effects` LMDB database.

    - `king clear-fx PIER`: Deletes all collected effects.

    - `king full-replay PIER`: Replays the whole event log events, print
      any failures. On success, replace the snapshot.


    # Full Replay -- An Integration Test

    - Copy the event log:

      - Create a new event log at the destination.
      - Stream events from the first event log.
      - Parse each event.
      - Re-Serialize each event.
      - Verify that the round-trip was successful.
      - Write the event into the new database.

    - Replay the event log at the destination.
      - If `--collect-fx` is set, then record effects as well.

    - Snapshot.

    - Verify that the final mug is the same as it was before.

    # Implement Remaining Serf Flags

    - `DebugRam`: Memory debugging.
    - `DebugCpu`: Profiling
    - `CheckCorrupt`: Heap Corruption Tests
    - `CheckFatal`: TODO What is this?
    - `Verbose`: TODO Just the `-v` flag?
    - `DryRun`: TODO Just the `-N` flag?
    - `Quiet`: TODO Just the `-q` flag?
    - `Hashless`: Don't use hashboard for jets.
-}

module Main (main) where

import UrbitPrelude

import Arvo
import Data.Acquire
import Data.Conduit
import Data.Conduit.List       hiding (catMaybes, map, replicate, take)
import Data.RAcquire
import Network.HTTP.Client.TLS
import Noun                    hiding (Parser)
import Noun.Atom
import Noun.Conversions        (cordToUW)
import PierConfig
import RIO.Directory
import Vere.Pier
import Vere.Pier.Types
import Vere.Serf

import Control.Concurrent   (myThreadId, runInBoundThread)
import Control.Exception    (AsyncException(UserInterrupt))
import Control.Lens         ((&))
import Data.Default         (def)
import KingApp              (runApp, runPierApp)
import System.Environment   (getProgName)
import System.Posix.Signals (Handler(Catch), installHandler, sigTERM)
import System.Random        (randomIO)
import Text.Show.Pretty     (pPrint)
import Urbit.Time           (Wen)
import Vere.Dawn
import Vere.LockFile        (lockFile)

import qualified CLI                         as CLI
import qualified Data.Set                    as Set
import qualified Data.Text                   as T
import qualified EventBrowser                as EventBrowser
import qualified Network.HTTP.Client         as C
import qualified System.IO.LockFile.Internal as Lock
import qualified Urbit.Ob                    as Ob
import qualified Vere.Log                    as Log
import qualified Vere.Pier                   as Pier
import qualified Vere.Serf                   as Serf
import qualified Vere.Term                   as Term

--------------------------------------------------------------------------------

zod :: Ship
zod = 0

--------------------------------------------------------------------------------

removeFileIfExists :: HasLogFunc env => FilePath -> RIO env ()
removeFileIfExists pax = do
  exists <- doesFileExist pax
  when exists $ do
      removeFile pax

--------------------------------------------------------------------------------

toSerfFlags :: CLI.Opts -> Serf.Flags
toSerfFlags CLI.Opts{..} = catMaybes m
  where
    -- TODO: This is not all the flags.
    m = [ from oQuiet Serf.Quiet
        , from oTrace Serf.Trace
        , from oHashless Serf.Hashless
        , from oQuiet Serf.Quiet
        , from oVerbose Serf.Verbose
        , from oDryRun Serf.DryRun
        ]
    from True flag = Just flag
    from False _   = Nothing


toPierConfig :: FilePath -> CLI.Opts -> PierConfig
toPierConfig pierPath CLI.Opts{..} = PierConfig
  { pcPierPath = pierPath
  , pcNetworking = if oLocalhost then NetworkLocalhost
                   else NetworkNormal
  , pcAmesPort = oAmesPort
  }

tryBootFromPill :: (HasPierConfig e, HasLogFunc e)
                => Bool -> Pill -> Bool -> Serf.Flags -> Ship
                -> LegacyBootEvent
                -> RIO e ()
tryBootFromPill oExit pill lite flags ship boot =
  do
    runOrExitImmediately bootedPier oExit
  where
    bootedPier = do
        getPierPath >>= lockFile
        rio $ logTrace "Starting boot"
        sls <- Pier.booted pill lite flags ship boot
        rio $ logTrace "Completed boot"
        pure sls

runOrExitImmediately :: (HasPierConfig e, HasLogFunc e)
                     => RAcquire e (Serf e, Log.EventLog, SerfState)
                     -> Bool
                     -> RIO e ()
runOrExitImmediately getPier oExit =
  do
    rwith getPier $ if oExit then shutdownImmediately else runPier
  where
    shutdownImmediately (serf, log, ss) = do
        logTrace "Sending shutdown signal"
        logTrace $ displayShow ss
        io $ threadDelay 500000
        ss <- shutdown serf 0
        logTrace $ displayShow ss
        logTrace "Shutdown!"

    runPier sls = do
        runRAcquire $ Pier.pier sls

tryPlayShip :: (HasPierConfig e, HasLogFunc e)
            => Bool -> Serf.Flags -> RIO e ()
tryPlayShip oExit flags = runOrExitImmediately resumeShip oExit
  where
    resumeShip = do
        getPierPath >>= lockFile
        rio $ logTrace "RESUMING SHIP"
        sls <- Pier.resumed flags
        rio $ logTrace "SHIP RESUMED"
        pure sls

runAcquire :: (MonadUnliftIO m,  MonadIO m)
           => Acquire a -> m a
runAcquire act = with act pure

runRAcquire :: (MonadUnliftIO (m e),  MonadIO (m e), MonadReader e (m e))
            => RAcquire e a -> m e a
runRAcquire act = rwith act pure

tryResume :: (HasPierConfig e, HasLogFunc e) => Serf.Flags -> RIO e ()
tryResume flags = do
    rwith resumedPier $ \(serf, log, ss) -> do
        logTrace (displayShow ss)
        threadDelay 500000
        ss <- shutdown serf 0
        logTrace (displayShow ss)
        logTrace "Resumed!"
  where
    resumedPier = do
        getPierPath >>= lockFile
        Pier.resumed flags

tryFullReplay :: (HasPierConfig e, HasLogFunc e) => Serf.Flags -> RIO e ()
tryFullReplay flags = do
    wipeSnapshot
    tryResume flags
  where
    wipeSnapshot = do
        shipPath <- getPierPath
        logTrace "wipeSnapshot"
        logDebug $ display $ pack @Text ("Wiping " <> north shipPath)
        logDebug $ display $ pack @Text ("Wiping " <> south shipPath)
        removeFileIfExists (north shipPath)
        removeFileIfExists (south shipPath)

    north shipPath = shipPath <> "/.urb/chk/north.bin"
    south shipPath = shipPath <> "/.urb/chk/south.bin"


--------------------------------------------------------------------------------

checkEvs :: forall e. HasLogFunc e => FilePath -> Word64 -> Word64 -> RIO e ()
checkEvs pierPath first last = do
    rwith (Log.existing logPath) $ \log -> do
        let ident = Log.identity log
        logTrace (displayShow ident)
        runConduit $ Log.streamEvents log first
                  .| showEvents first (fromIntegral $ lifecycleLen ident)
  where
    logPath :: FilePath
    logPath = pierPath <> "/.urb/log"

    showEvents :: EventId -> EventId -> ConduitT ByteString Void (RIO e) ()
    showEvents eId _ | eId > last = pure ()
    showEvents eId cycle          =
        await >>= \case
            Nothing -> lift $ logTrace "Everything checks out."
            Just bs -> do
                lift $ do
                    n <- io $ cueBSExn bs
                    when (eId > cycle) $ do
                        (mug, wen, evNoun) <- unpackJob n
                        fromNounErr evNoun &
                            either (logError . displayShow) pure
                showEvents (succ eId) cycle

    unpackJob :: Noun -> RIO e (Mug, Wen, Noun)
    unpackJob = io . fromNounExn

--------------------------------------------------------------------------------

{-
    This runs the serf at `$top/.tmpdir`, but we disable snapshots,
    so this should never actually be created. We just do this to avoid
    letting the serf use an existing snapshot.
-}
collectAllFx :: ∀e. HasLogFunc e => FilePath -> RIO e ()
collectAllFx top = do
    logTrace $ display $ pack @Text top
    rwith collectedFX $ \() ->
        logTrace "Done collecting effects!"
  where
    tmpDir :: FilePath
    tmpDir = top <> "/.tmpdir"

    collectedFX :: RAcquire e ()
    collectedFX = do
        lockFile top
        log  <- Log.existing (top <> "/.urb/log")
        serf <- Serf.run (Serf.Config tmpDir serfFlags)
        rio $ Serf.collectFX serf log

    serfFlags :: Serf.Flags
    serfFlags = [Serf.Hashless, Serf.DryRun]

--------------------------------------------------------------------------------

{-
    Interesting
-}
testPill :: HasLogFunc e => FilePath -> Bool -> Bool -> RIO e ()
testPill pax showPil showSeq = do
  putStrLn "Reading pill file."
  pillBytes <- readFile pax

  putStrLn "Cueing pill file."
  pillNoun <- io $ cueBS pillBytes & either throwIO pure

  putStrLn "Parsing pill file."
  pill <- fromNounErr pillNoun & either (throwIO . uncurry ParseErr) pure

  putStrLn "Using pill to generate boot sequence."
  bootSeq <- generateBootSeq zod pill False (Fake $ Ship 0)

  putStrLn "Validate jam/cue and toNoun/fromNoun on pill value"
  reJam <- validateNounVal pill

  putStrLn "Checking if round-trip matches input file:"
  unless (reJam == pillBytes) $ do
    putStrLn "    Our jam does not match the file...\n"
    putStrLn "    This is surprising, but it is probably okay."

  when showPil $ do
      putStrLn "\n\n== Pill ==\n"
      io $ pPrint pill

  when showSeq $ do
      putStrLn "\n\n== Boot Sequence ==\n"
      io $ pPrint bootSeq

validateNounVal :: (HasLogFunc e, Eq a, ToNoun a, FromNoun a)
                => a -> RIO e ByteString
validateNounVal inpVal = do
    putStrLn "  jam"
    inpByt <- evaluate $ jamBS $ toNoun inpVal

    putStrLn "  cue"
    outNon <- cueBS inpByt & either throwIO pure

    putStrLn "  fromNoun"
    outVal <- fromNounErr outNon & either (throwIO . uncurry ParseErr) pure

    putStrLn "  toNoun"
    outNon <- evaluate (toNoun outVal)

    putStrLn "  jam"
    outByt <- evaluate $ jamBS outNon

    putStrLn "Checking if: x == cue (jam x)"
    unless (inpVal == outVal) $
        error "Value fails test: x == cue (jam x)"

    putStrLn "Checking if: jam x == jam (cue (jam x))"
    unless (inpByt == outByt) $
        error "Value fails test: jam x == jam (cue (jam x))"

    pure outByt

--------------------------------------------------------------------------------

pillFrom :: CLI.PillSource -> RIO e Pill

pillFrom (CLI.PillSourceFile pillPath) = do
  putStrLn $ "boot: reading pill from " ++ pack pillPath
  io (loadFile pillPath >>= either throwIO pure)

pillFrom (CLI.PillSourceURL url) = do
  putStrLn $ "boot: retrieving pill from " ++ pack url
  -- Get the jamfile with the list of stars accepting comets right now.
  manager <- io $ C.newManager tlsManagerSettings
  request <- io $ C.parseRequest url
  response <- io $ C.httpLbs (C.setRequestCheckStatus request) manager
  let body = toStrict $ C.responseBody response

  noun <- cueBS body & either throwIO pure
  fromNounErr noun & either (throwIO . uncurry ParseErr) pure

newShip :: forall e. HasLogFunc e => CLI.New -> CLI.Opts -> RIO e ()
newShip CLI.New{..} opts
  | CLI.BootComet <- nBootType = do
      pill <- pillFrom nPillSource
      putStrLn "boot: retrieving list of stars currently accepting comets"
      starList <- dawnCometList
      putStrLn ("boot: " ++ (tshow $ length starList) ++
                " star(s) currently accepting comets")
      putStrLn "boot: mining a comet"
      eny <- io $ randomIO
      let seed = mineComet (Set.fromList starList) eny
      putStrLn ("boot: found comet " ++ (renderShip (sShip seed)))
      bootFromSeed pill seed

  | CLI.BootFake name <- nBootType = do
      pill <- pillFrom nPillSource
      ship <- shipFrom name
      runTryBootFromPill pill name ship (Fake ship)

  | CLI.BootFromKeyfile keyFile <- nBootType = do
      text <- readFileUtf8 keyFile
      asAtom <- case cordToUW (Cord $ T.strip text) of
        Nothing -> error "Couldn't parse keyfile. Hint: keyfiles start with 0w?"
        Just (UW a) -> pure a

      asNoun <- cueExn asAtom
      seed :: Seed <- case fromNoun asNoun of
        Nothing -> error "Keyfile does not seem to contain a seed."
        Just s  -> pure s

      pill <- pillFrom nPillSource

      bootFromSeed pill seed

  where
    shipFrom :: Text -> RIO e Ship
    shipFrom name = case Ob.parsePatp name of
      Left x  -> error "Invalid ship name"
      Right p -> pure $ Ship $ fromIntegral $ Ob.fromPatp p

    pierPath :: Text -> FilePath
    pierPath name = case nPierPath of
      Just x  -> x
      Nothing -> "./" <> unpack name

    nameFromShip :: Ship -> RIO e Text
    nameFromShip s = name
      where
        nameWithSig = Ob.renderPatp $ Ob.patp $ fromIntegral s
        name = case stripPrefix "~" nameWithSig of
          Nothing -> error "Urbit.ob didn't produce string with ~"
          Just x  -> pure x

    bootFromSeed :: Pill -> Seed -> RIO e ()
    bootFromSeed pill seed = do
      ethReturn <- dawnVent seed

      case ethReturn of
        Left x -> error $ unpack x
        Right dawn -> do
          let ship = sShip $ dSeed dawn
          name <- nameFromShip ship
          runTryBootFromPill pill name ship (Dawn dawn)

    flags = toSerfFlags opts

    -- Now that we have all the information for running an application with a
    -- PierConfig, do so.
    runTryBootFromPill pill name ship bootEvent = do
      let config = toPierConfig (pierPath name) opts
      io $ runPierApp config $
        tryBootFromPill (CLI.oExit opts) pill nLite flags ship bootEvent


runShip :: CLI.Run -> CLI.Opts -> IO ()
runShip (CLI.Run pierPath) opts = do
    let config = toPierConfig pierPath opts
    runPierApp config $ tryPlayShip (CLI.oExit opts) (toSerfFlags opts)


startBrowser :: HasLogFunc e => FilePath -> RIO e ()
startBrowser pierPath = runRAcquire $ do
    lockFile pierPath
    log <- Log.existing (pierPath <> "/.urb/log")
    rio $ EventBrowser.run log

checkDawn :: HasLogFunc e => FilePath -> RIO e ()
checkDawn keyfilePath = do
  -- The keyfile is a jammed Seed then rendered in UW format
  text <- readFileUtf8 keyfilePath
  asAtom <- case cordToUW (Cord $ T.strip text) of
    Nothing -> error "Couldn't parse keyfile. Hint: keyfiles start with 0w?"
    Just (UW a) -> pure a

  asNoun <- cueExn asAtom
  seed :: Seed <- case fromNoun asNoun of
    Nothing -> error "Keyfile does not seem to contain a seed."
    Just s  -> pure s

  print $ show seed

  e <- dawnVent seed
  print $ show e


checkComet :: HasLogFunc e => RIO e ()
checkComet = do
  starList <- dawnCometList
  putStrLn "Stars currently accepting comets:"
  let starNames = map (Ob.renderPatp . Ob.patp . fromIntegral) starList
  print starNames
  putStrLn "Trying to mine a comet..."
  eny <- io $ randomIO
  let s = mineComet (Set.fromList starList) eny
  print s

main :: IO ()
main = do
    mainTid <- myThreadId

    let onTermSig = throwTo mainTid UserInterrupt

    installHandler sigTERM (Catch onTermSig) Nothing

    CLI.parseArgs >>= \case
        CLI.CmdRun r o                            -> runShip r o
        CLI.CmdNew n o                            -> runApp $ newShip n o
        CLI.CmdBug (CLI.CollectAllFX pax)         -> runApp $ collectAllFx pax
        CLI.CmdBug (CLI.EventBrowser pax)         -> runApp $ startBrowser pax
        CLI.CmdBug (CLI.ValidatePill pax pil seq) -> runApp $ testPill pax pil seq
        CLI.CmdBug (CLI.ValidateEvents pax f l)   -> runApp $ checkEvs pax f l
        CLI.CmdBug (CLI.ValidateFX pax f l)       -> runApp $ checkFx  pax f l
        CLI.CmdBug (CLI.CheckDawn pax)            -> runApp $ checkDawn pax
        CLI.CmdBug CLI.CheckComet                 -> runApp $ checkComet
        CLI.CmdCon port                           -> runApp $ connTerm port


--------------------------------------------------------------------------------

connTerm :: ∀e. HasLogFunc e => Word16 -> RIO e ()
connTerm port =
    Term.runTerminalClient (fromIntegral port)

--------------------------------------------------------------------------------

checkFx :: HasLogFunc e
        => FilePath -> Word64 -> Word64 -> RIO e ()
checkFx pierPath first last =
    rwith (Log.existing logPath) $ \log ->
        runConduit $ streamFX log first last
                  .| tryParseFXStream
  where
    logPath = pierPath <> "/.urb/log"

streamFX :: HasLogFunc e
         => Log.EventLog -> Word64 -> Word64
         -> ConduitT () ByteString (RIO e) ()
streamFX log first last = do
    Log.streamEffectsRows log first .| loop
  where
    loop = await >>= \case Nothing                     -> pure ()
                           Just (eId, bs) | eId > last -> pure ()
                           Just (eId, bs)              -> yield bs >> loop

tryParseFXStream :: HasLogFunc e => ConduitT ByteString Void (RIO e) ()
tryParseFXStream = loop
  where
    loop = await >>= \case
        Nothing -> pure ()
        Just bs -> do
            n <- liftIO (cueBSExn bs)
            fromNounErr n & either (logError . displayShow) pure
            loop


{-
tryCopyLog :: IO ()
tryCopyLog = do
  let logPath      = "/Users/erg/src/urbit/zod/.urb/falselog/"
      falselogPath = "/Users/erg/src/urbit/zod/.urb/falselog2/"

  persistQ <- newTQueueIO
  releaseQ <- newTQueueIO
  (ident, nextEv, events) <-
      with (do { log <- Log.existing logPath
               ; Pier.runPersist log persistQ (writeTQueue releaseQ)
               ; pure log
               })
        \log -> do
          ident  <- pure $ Log.identity log
          events <- runConduit (Log.streamEvents log 1 .| consume)
          nextEv <- Log.nextEv log
          pure (ident, nextEv, events)

  print ident
  print nextEv
  print (length events)

  persistQ2 <- newTQueueIO
  releaseQ2 <- newTQueueIO
  with (do { log <- Log.new falselogPath ident
           ; Pier.runPersist log persistQ2 (writeTQueue releaseQ2)
           ; pure log
           })
    $ \log2 -> do
      let writs = zip [1..] events <&> \(id, a) ->
                      (Writ id Nothing a, [])

      print "About to write"

      for_ writs $ \w ->
        atomically (writeTQueue persistQ2 w)

      print "About to wait"

      replicateM_ 100 $ do
        atomically $ readTQueue releaseQ2

      print "Done"
-}
