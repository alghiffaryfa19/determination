# Aurora website

Static, dependency-free project site with separate home, architecture, and
hardware-proof pages.

```sh
cd website
python3 -m http.server 8080
```

Open `http://localhost:8080`.

Repository buttons derive the owner automatically on GitHub Pages. Other hosts
can set the `aurora-repository-url` meta value in each page; the buttons
stay hidden when no repository URL is configured.
