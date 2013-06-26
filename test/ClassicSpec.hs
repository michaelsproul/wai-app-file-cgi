{-# LANGUAGE OverloadedStrings #-}

module ClassicSpec where

import Control.Applicative
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Conduit
import Network.HTTP.Conduit
import qualified Network.HTTP.Types as H
import Test.Hspec

spec :: Spec
spec = do
    describe "cgiApp" $ do
        it "accepts POST" $ do
            let url = "http://127.0.0.1:2345/cgi-bin/echo-env/pathinfo?query=foo"
            bdy <- responseBody <$> sendPOST url "foo bar.\nbaz!\n"
            ans <- BL.readFile "test/data/post"
            bdy `shouldBe` ans
        it "causes 500 if the CGI script does not exist" $ do
            let url = "http://127.0.0.1:2345/cgi-bin/broken"
            sc <- responseStatus <$> sendPOST url "foo bar.\nbaz!\n"
            sc `shouldBe` H.internalServerError500

    describe "fileApp" $ do
        it "returns index.html for /" $ do
            let url = "http://127.0.0.1:2345/"
            rsp <- simpleHttp url
            ans <- BL.readFile "test/html/index.html"
            rsp `shouldBe` ans
        it "returns 400 if not exist" $ do
            let url = "http://127.0.0.1:2345/dummy"
            req <- parseUrl url
            sc <- responseStatus <$> safeHttpLbs req
            sc `shouldBe` H.notFound404
        it "returns Japanese HTML if language is specified" $ do
            let url = "http://127.0.0.1:2345/ja/"
            bdy <- responseBody <$> sendGET url [("Accept-Language", "ja, en;q=0.7")]
            ans <- BL.readFile "test/html/ja/index.html.ja"
            bdy `shouldBe` ans
        it "returns 304 if not changed" $ do
            let url = "http://127.0.0.1:2345/"
            hdr <- responseHeaders <$> sendGET url []
            let Just lm = lookup "Last-Modified" hdr
            sc <- responseStatus <$> sendGET url [("If-Modified-Since", lm)]
            sc `shouldBe` H.notModified304
        it "can handle partial request" $ do
            let url = "http://127.0.0.1:2345/"
                ans = "html>\n<html"
            bdy <- responseBody <$> sendGET url [("Range", "bytes=10-20")]
            bdy `shouldBe` ans
        it "can handle HEAD" $ do
            let url = "http://127.0.0.1:2345/"
            sc <- responseStatus <$> sendHEAD url []
            sc `shouldBe` H.ok200
        it "returns 404 for HEAD if not exist" $ do
            let url = "http://127.0.0.1:2345/dummy"
            sc <- responseStatus <$> sendHEAD url []
            sc `shouldBe` H.notFound404
        it "can handle HEAD even if language is specified" $ do
            let url = "http://127.0.0.1:2345/ja/"
            sc <- responseStatus <$> sendHEAD url [("Accept-Language", "ja, en;q=0.7")]
            sc `shouldBe` H.ok200
        it "returns 304 for HEAD if not modified" $ do
            let url = "http://127.0.0.1:2345/"
            hdr <- responseHeaders <$> sendHEAD url []
            let Just lm = lookup "Last-Modified" hdr
            sc <- responseStatus <$> sendHEAD url [("If-Modified-Since", lm)]
            sc `shouldBe` H.notModified304
        it "redirects to dir/ if trailing slash is missing" $ do
            let url = "http://127.0.0.1:2345/redirect"
            rsp <- simpleHttp url
            ans <- BL.readFile "test/html/redirect/index.html"
            rsp `shouldBe` ans


----------------------------------------------------------------

sendGET ::String -> H.RequestHeaders -> IO (Response BL.ByteString)
sendGET url hdr = do
    req' <- parseUrl url
    let req = req' { requestHeaders = hdr }
    safeHttpLbs req

sendHEAD :: String -> H.RequestHeaders -> IO (Response BL.ByteString)
sendHEAD url hdr = do
    req' <- parseUrl url
    let req = req' {
            requestHeaders = hdr
          , method = "HEAD"
          }
    safeHttpLbs req

sendPOST :: String -> BL.ByteString -> IO (Response BL.ByteString)
sendPOST url body = do
    req' <- parseUrl url
    let req = req' {
            method = "POST"
          , requestBody = RequestBodyLBS body
          }
    safeHttpLbs req

----------------------------------------------------------------

safeHttpLbs :: Request (ResourceT IO) -> IO (Response BL.ByteString)
safeHttpLbs req = withManager $ httpLbs req {
    checkStatus = \_ _ _  -> Nothing -- prevent throwing an error
  }
