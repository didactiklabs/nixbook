let
  goreadUrls = ''
    categories:
      # - name: News
      #   desc: General News
      #   subscriptions:
      - name: IT Tech French
        desc: Tech, IT stuffs
        subscriptions:
          - name: Zwindler Blog
            desc: News from Zwindler
            url: https://blog.zwindler.fr/index.xml
          - name: Korben Blog
            desc: News from Korben
            url: https://korben.info/feed
          - name: FrenchWeb
            desc: News from FrenchWeb
            url: https://www.frenchweb.fr/feed
          - name: FredZone
            desc: News from FredZone
            url: https://feeds.feedburner.com/Fredzone
      - name: IT Tech
        desc: Tech, IT stuffs
        subscriptions:
          - name: Hacker News
            desc: Hacker News
            url: https://hnrss.org/frontpage
          - name: LifeHacker News
            desc: LifeHacker News
            url: https://lifehacker.com/feed/rss
          - name: ByteByteGo
            desc: News from ByteByteGo
            url: https://blog.bytebytego.com/feed
          - name: ArsTechnica
            desc: News from ArsTechnica
            url: https://feeds.arstechnica.com/arstechnica/index
          - name: Terminal Trove
            desc: News from Terminal Trove
            url: https://terminaltrove.com/new.xml
          - name: r/commandline
            desc: News from r/commandline
            url: https://old.reddit.com/r/commandline/.rss
          - name: r/selfhosted
            desc: News from r/selfhosted
            url: https://old.reddit.com/r/selfhosted/.rss
          - name: r/coolgithubprojects
            desc: News from r/coolgithubprojects
            url: https://old.reddit.com/r/coolgithubprojects/.rss
      - name: Sciences
        desc: About Sciences
        subscriptions:
          - name: Popular Sciences
            desc: News from Popular Sciences
            url: https://www.popsci.com/rss.xml
          - name: DamnInteresting
            desc: News from DamnInteresting
            url: https://feeds.feedburner.com/damninteresting/all
      - name: Travels
        desc: About Travels
        subscriptions:
          - name: ThePointsGuy
            desc: News from ThePointsGuy
            url: https://thepointsguy.com/feed/
          - name: LonelyPlanet
            desc: News from LonelyPlanet
            url: https://www.lonelyplanet.com/articles/feature/feed
      - name: Anime French
        desc: Anime News
        subscriptions:
          - name: Japananime News
            desc: News from Japananime
            url: https://www.japananime.fr/feed
          - name: Animeland News
            desc: News from Animeland
            url: https://animeland.fr/feed
      - name: Anime
        desc: Anime News
        subscriptions:
          - name: Crunshyroll News
            desc: News from Crunshyroll
            url: https://cr-news-api-service.prd.crunchyrollsvc.com/v1/en-US/rss
          - name: MyAnimeList News
            desc: News from MyAnimeList
            url: https://myanimelist.net/rss/news.xml
          - name: AlltheAnime News
            desc: News from AlltheAnime
            url: https://blog.alltheanime.com/feed
      - name: Gaming
        desc: Gaming News
        subscriptions:
          - name: IGN News
            desc: News from IGN
            url: https://www.ign.com/rss/articles/feed?tags=games
          - name: Cooptimus News
            desc: News from Cooptimus
            url: https://feeds.feedburner.com/Co-optimus
          - name: RockPaperShotGun News
            desc: News from RockPaperShotGun
            url: https://www.rockpapershotgun.com/feed/
          - name: Valve News
            desc: News from Valve
            url: https://store.steampowered.com/feeds/news/
  '';
in
{
  config = {
    home = {
      file = {
        ".config/goread/urls.yml" = {
          text = goreadUrls;
        };
      };
    };
  };
}
