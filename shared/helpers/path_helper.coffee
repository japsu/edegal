_ = require 'underscore'

charMap =
  'ä': 'a'
  'å': 'a'
  'ö': 'o'
  'ü': 'u'
  ' ': '-'
  '_': '-'
  '.': '-'

exports.slugify = (str) ->
  str = str.toLowerCase()
  str = _.map(str, (c) -> charMap[c] ? c).join('')
  str.replace(/[^a-z0-9-]/g, '')

exports.makeBreadcrumb = (albumsOrPictures...) ->
  parent = _.first albumsOrPictures
  breadcrumb = parent.breadcrumb ? parent.get?('breadcrumb')

  for albumOrPicture in albumsOrPictures
    breadcrumb = breadcrumb.concat [
      path: albumOrPicture.path ? albumOrPicture.get?('path') ? ''
      title: albumOrPicture.title ? albumOrPicture.get?('title') ? ''
    ]

  breadcrumb