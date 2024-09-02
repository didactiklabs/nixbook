let
  goreadUrls = ''
    categories:
      - name: News
        desc: General News
        subscriptions:
          - name: ArsTechnica
            desc: News from ArsTechnica
            url: https://feeds.arstechnica.com/arstechnica/index
      - name: IT Tech
        desc: Tech, IT stuffs
        subscriptions:
          - name: Zwindler Blog
            desc: News from Zwindler
            url: https://blog.zwindler.fr/index.xml
          - name: Hacker News
            desc: Hacker News
            url: https://hnrss.org/frontpage
          - name: ByteByteGo
            desc: News from ByteByteGo
            url: https://blog.bytebytego.com/feed
          - name: Terminal Trove
            desc: News from Terminal Trove
            url: https://terminaltrove.com/new.xml
          - name: r/selfhosted
            desc: News from r/selfhosted
            url: https://old.reddit.com/r/selfhosted/.rss
          - name: r/coolgithubprojects
            desc: News from r/coolgithubprojects
            url: https://old.reddit.com/r/coolgithubprojects/.rss
      - name: Anime
        desc: Anime News
        subscriptions:
          - name: Crunshyroll News
            desc: News from Crunshyroll
            url: https://cr-news-api-service.prd.crunchyrollsvc.com/v1/en-US/rss
          - name: MyAnimeList News
            desc: News from MyAnimeList
            url: https://myanimelist.net/rss/news.xml

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
