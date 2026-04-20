# Action Text

Action Textadds rich‑text editing to Rails. It uses the Trix editor, which supports formatting, links, quotes, lists, images, and galleries. Trix stores rich‑text content in a dedicated RichText model that belongs to any existing Active Record model. Embedded images and other attachments are saved via Active Storage and linked to the RichText model.

See the [Action Text Overview](https://guides.rubyonrails.org/action_text_overview.html) for more information.

## Development

The JavaScript is published as the npm package `@rails/actiontext` and also as `actiontext.js` through the asset pipeline (mirroring Trix as `trix.js`). After changing JavaScript or its Trix dependency, run `yarn build` and commit the generated files. Apply CSS modifications manually to `app/assets/stylesheets/trix.css`.

## License

Action Text is released under the MIT License.