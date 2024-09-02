let
  goreadUrls = ''
    categories:
      - name: News
        desc: News from around the world
        subscriptions:
          - name: BBC
            desc: News from the BBC
            url: http://feeds.bbci.co.uk/news/rss.xml
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
