import FootyKit
import Foundation

/// The local page hosting the YouTube IFrame Player API with YouTube's own controls. Only documented
/// player parameters and API calls are used; nothing is injected into or drawn over the player (ToS / RMF).
/// Annotations are off (`iv_load_policy=3`). The viewer's saved volume, mute and speed are applied to each video.
enum PlayerPage {
    /// Loaded with this base URL so WebKit sends the Referer YouTube requires for embeds (RMF, July 2025).
    static let baseURL = URL(string: "https://\(FootyKit.bundleIdentifier)")!

    static func html(videoId: String, muted: Bool, preferences: PlayerPreferences) -> String {
        // Video IDs are [A-Za-z0-9_-]; reject anything else rather than escaping.
        let safeId = videoId.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return """
            <!doctype html>
            <html><head><meta charset="utf-8">
            <style>
              html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
              #yt { position: absolute; inset: 0; width: 100%; height: 100%; }
            </style></head>
            <body><div id="yt"></div>
            <script>
              const post = (msg) => window.webkit.messageHandlers.player.postMessage(msg);
              let player = null, timer = null, applyRate = true, appliedAt = 0;
              const prefs = { volume: \(preferences.volume), muted: \(preferences.muted || muted), rate: \(preferences.playbackRate) };
              const tag = document.createElement('script');
              tag.src = 'https://www.youtube.com/iframe_api';
              tag.onerror = () => post({ type: 'error', code: -1 });
              document.head.appendChild(tag);

              function report() {
                if (!player || !player.getCurrentTime) return;
                post({ type: 'time', current: player.getCurrentTime() || 0, duration: player.getDuration() || 0,
                       volume: player.getVolume ? player.getVolume() : 100, muted: player.isMuted ? player.isMuted() : false,
                       rate: player.getPlaybackRate ? player.getPlaybackRate() : 1,
                       // The saved settings have taken effect, so what's reported now is the viewer's choice.
                       settled: !applyRate && Date.now() - appliedAt > 1500 });
              }

              window.onYouTubeIframeAPIReady = () => {
                player = new YT.Player('yt', {
                  width: '100%', height: '100%', videoId: '\(safeId)',
                  playerVars: { autoplay: 1, controls: 1, fs: 1, rel: 0, iv_load_policy: 3, playsinline: 1,
                                enablejsapi: 1, origin: '\(baseURL.absoluteString)' },
                  events: {
                    onReady: (e) => {
                      e.target.setVolume(prefs.volume);
                      if (prefs.muted) e.target.mute();
                      e.target.playVideo();
                      post({ type: 'ready' });
                    },
                    onStateChange: (e) => {
                      post({ type: 'state', state: e.data });
                      // Speed can only be set once a video is playing; re-applied for each new video.
                      if (e.data === 1 && applyRate) {
                        applyRate = false;
                        appliedAt = Date.now();
                        if (prefs.rate !== 1) player.setPlaybackRate(prefs.rate);
                      }
                      // At the end the app either loads the next queued video or destroys the player,
                      // so YouTube's related-videos grid never stays on screen.
                      if (e.data === 0) post({ type: 'ended' });
                    },
                    onError: (e) => { post({ type: 'error', code: e.data }); destroy(); },
                  },
                });
                timer = setInterval(report, 250);
              };

              // Remove the player at the end so YouTube's related-videos grid never appears.
              function destroy() {
                if (timer) { clearInterval(timer); timer = null; }
                if (player) { player.destroy(); player = null; }
              }

              window.footy = {
                play: () => player && player.playVideo(),
                pause: () => player && player.pauseVideo(),
                seekBy: (s) => player && player.seekTo(Math.max(0, player.getCurrentTime() + s), true),
                seekTo: (s) => player && player.seekTo(s, true),
                load: (id, rate) => { if (player) { prefs.rate = rate; applyRate = true; player.loadVideoById(id); } },
                setVolume: (v) => { if (player) { player.unMute(); player.setVolume(v); } },
                mute: (m) => player && (m ? player.mute() : player.unMute()),
                destroy,
              };
            </script></body></html>
            """
    }
}
