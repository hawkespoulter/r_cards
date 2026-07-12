# Short commit SHA for the currently running build, shown in the profile
# dropdown so it's easy to tell which deploy is live. HEROKU_SLUG_COMMIT is
# only present when the "runtime-dyno-metadata" labs feature is enabled
# (`heroku labs:enable runtime-dyno-metadata`) — without it, or in local
# development, falls back to reading the working tree's own git SHA (the
# deployed slug has no .git directory, so this rescue path only ever fires
# outside Heroku).
Rails.application.config.build_version =
  ENV["HEROKU_SLUG_COMMIT"]&.first(7).presence ||
  begin
    sha = Dir.chdir(Rails.root) { `git rev-parse --short HEAD`.strip }
    sha.presence if $?&.success?
  rescue StandardError
    nil
  end || "dev"
