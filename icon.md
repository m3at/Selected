# Icon Size 

1024*1024 px size, transparent background, png format

Content should be 824*824 px

# Generation Method
Create a folder named `icons.iconset`:

``` bash
mkdir icons.iconset 
```

Generate PNG images of various sizes.
Use the Terminal to quickly create image files of different sizes.

```bash
sips -z 16 16 icon.png -o icons.iconset/icon_16x16.png 
sips -z 32 32 icon.png -o icons.iconset/icon_16x16@2x.png 
sips -z 32 32 icon.png -o icons.iconset/icon_32x32.png 
sips -z 64 64 icon.png -o icons.iconset/icon_32x32@2x.png 
sips -z 128 128 icon.png -o icons.iconset/icon_128x128.png 
sips -z 256 256 icon.png -o icons.iconset/icon_128x128@2x.png 
sips -z 256 256 icon.png -o icons.iconset/icon_256x256.png 
sips -z 512 512 icon.png -o icons.iconset/icon_256x256@2x.png 
sips -z 512 512 icon.png -o icons.iconset/icon_512x512.png 
sips -z 1024 1024 icon.png -o icons.iconset/icon_512x512@2x.png 
```

# Import
Import into `AppIcon` in `Assets`.
