import { defineConfig } from 'vitepress'

const repo = 'https://github.com/didactiklabs/nixbook'
// Served by GitHub Pages as a project site: https://didactiklabs.github.io/nixbook/
// Set DOCS_BASE=/ when serving from a custom domain.
const base = process.env.DOCS_BASE ?? '/nixbook/'

// Option descriptions (MODULES.md) and KEYBINDS.md contain placeholders such
// as <user> or <leader> in plain text. Rendered as raw HTML, Vue would read
// them as unclosed elements, so inline HTML is escaped unless it is a comment
// or a real HTML tag.
const htmlTag =
  /^<\/?(a|abbr|b|br|code|del|details|div|em|i|img|kbd|mark|p|s|small|span|strong|sub|summary|sup|u)(\s|\/?>)/i

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: 'Nixbook',
  description:
    'Declarative NixOS configuration for a fleet of Wayland laptops and desktops',
  base,
  lastUpdated: true,
  // localhost URLs (dev server, CUPS) are not pages of this site.
  ignoreDeadLinks: 'localhostLinks',
  cleanUrls: true,

  // docs/MODULES.md is generated (generate-docs) and included by
  // reference/options.md; it is not a page of its own.
  srcExclude: ['MODULES.md'],

  head: [['link', { rel: 'icon', type: 'image/svg+xml', href: `${base}logo.svg` }]],

  markdown: {
    theme: { light: 'github-light', dark: 'github-dark' },
    config: (md) => {
      md.renderer.rules.html_inline = (tokens, idx) => {
        const html = tokens[idx].content
        return html.startsWith('<!--') || htmlTag.test(html)
          ? html
          : md.utils.escapeHtml(html)
      }
    },
  },

  themeConfig: {
    // https://vitepress.dev/reference/default-theme-config
    logo: '/logo.svg',
    search: {
      provider: 'local',
    },
    editLink: {
      pattern: `${repo}/edit/main/docs/:path`,
      text: 'Edit this page on GitHub',
    },
    outline: [2, 3],

    nav: [
      { text: 'Guide', link: '/guide/introduction', activeMatch: '/guide/' },
      { text: 'Installation', link: '/installation/', activeMatch: '/installation/' },
      { text: 'Machines', link: '/machines/', activeMatch: '/machines/' },
      {
        text: 'Features',
        items: [
          { text: 'System (NixOS modules)', link: '/system/core' },
          { text: 'User (Home Manager modules)', link: '/user/shell' },
          { text: 'Desktop', link: '/desktop/' },
          { text: 'nixbook-shell', link: '/nixbook-shell/' },
          { text: 'Custom packages', link: '/packages/' },
        ],
      },
      { text: 'Development', link: '/development/testing', activeMatch: '/development/' },
      {
        text: 'Reference',
        items: [
          { text: 'Module options', link: '/reference/options' },
          { text: 'Keybindings', link: '/desktop/keybindings' },
        ],
      },
    ],

    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'Introduction', link: '/guide/introduction' },
          { text: 'Architecture', link: '/guide/architecture' },
          { text: 'Development environment', link: '/guide/development-environment' },
        ],
      },
      {
        text: 'Installation',
        collapsed: false,
        items: [
          { text: 'Overview', link: '/installation/' },
          { text: 'Installer ISO', link: '/installation/iso' },
          { text: 'Secure Boot', link: '/installation/secure-boot' },
          { text: 'Deploy & update', link: '/installation/deploy-and-update' },
          { text: 'Home Manager on other distros', link: '/installation/home-manager-standalone' },
        ],
      },
      {
        text: 'Machines',
        collapsed: false,
        items: [
          { text: 'The fleet', link: '/machines/' },
          { text: 'Machine profiles', link: '/machines/profiles' },
          { text: 'Adding a machine or user', link: '/machines/adding-a-machine' },
        ],
      },
      {
        text: 'System (NixOS modules)',
        collapsed: false,
        items: [
          { text: 'Core system', link: '/system/core' },
          { text: 'Security', link: '/system/security' },
          { text: 'Networking & VPN', link: '/system/networking' },
          { text: 'Hardware & power', link: '/system/hardware' },
          { text: 'Gaming, streaming & sim racing', link: '/system/gaming-and-streaming' },
          { text: 'Input methods', link: '/system/input-methods' },
        ],
      },
      {
        text: 'User (Home Manager modules)',
        collapsed: false,
        items: [
          { text: 'Shell & terminal', link: '/user/shell' },
          { text: 'Development tools', link: '/user/development' },
          { text: 'AI coding workspaces (ocm)', link: '/user/ai-workspaces' },
          { text: 'Kubernetes', link: '/user/kubernetes' },
          { text: 'Desktop applications', link: '/user/applications' },
          { text: 'Theming & fonts', link: '/user/theming' },
        ],
      },
      {
        text: 'Desktop',
        collapsed: false,
        items: [
          { text: 'Overview', link: '/desktop/' },
          { text: 'Niri', link: '/desktop/niri' },
          { text: 'Sway', link: '/desktop/sway' },
          { text: 'Login (greetd)', link: '/desktop/login' },
          { text: 'DankMaterialShell', link: '/desktop/dms' },
          { text: 'Keybindings', link: '/desktop/keybindings' },
        ],
      },
      {
        text: 'nixbook-shell',
        collapsed: false,
        items: [
          { text: 'Overview', link: '/nixbook-shell/' },
          { text: 'Settings', link: '/nixbook-shell/settings' },
          { text: 'Themes & colours', link: '/nixbook-shell/themes' },
          { text: 'Bar, launcher & panels', link: '/nixbook-shell/bar-and-panels' },
          { text: 'Notifications', link: '/nixbook-shell/notifications' },
          { text: 'Calendar & tasks', link: '/nixbook-shell/calendar' },
          { text: 'Desktop widgets & wallpapers', link: '/nixbook-shell/desktop-and-wallpapers' },
          { text: 'Media & phone', link: '/nixbook-shell/media' },
          { text: 'Screenshots & recording', link: '/nixbook-shell/screenshots' },
          { text: 'Window layouts', link: '/nixbook-shell/window-layouts' },
          { text: 'Lock & login screens', link: '/nixbook-shell/lock-and-login' },
          { text: 'AI chat & config assistant', link: '/nixbook-shell/ai-assistant' },
          { text: 'Desktop control for AI agents', link: '/nixbook-shell/desktop-agents' },
          { text: "The agents' own desktop", link: '/nixbook-shell/agent-desktop' },
        ],
      },
      {
        text: 'Packages',
        items: [{ text: 'Custom packages', link: '/packages/' }],
      },
      {
        text: 'Development',
        collapsed: false,
        items: [
          { text: 'Testing', link: '/development/testing' },
          { text: 'CI/CD', link: '/development/ci-cd' },
          { text: 'Dependencies (npins)', link: '/development/dependencies' },
          { text: 'Contributing', link: '/development/contributing' },
          { text: 'This documentation', link: '/development/documentation' },
        ],
      },
      {
        text: 'Reference',
        items: [
          { text: 'Module options', link: '/reference/options' },
          { text: 'Keybindings', link: '/desktop/keybindings' },
        ],
      },
    ],

    socialLinks: [{ icon: 'github', link: repo }],

    footer: {
      message: 'Everything as code — built with Nix, deployed with Colmena.',
      copyright: 'Copyright © 2026 DidactikLabs contributors',
    },
  },
})
