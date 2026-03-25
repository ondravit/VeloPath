# Ukázka struktury našich GeoJSON dat

Velké soubory jsou ignorovány, aby se šetřily tokeny. Všechny načítané soubory mají tuto strukturu (LineString a properties obsahující `stav_sil`):

```json
{
  "type": "FeatureCollection",
  "name": "Silnice_KHK_all_merged",
  "crs": {
    "type": "name",
    "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" }
  },
  "features": [
    {
      "type": "Feature",
      "properties": {
        "highway": "track",
        "surface": "asphalt",
        "tracktype": "grade1",
        "bicycle": null,
        "stav_sil": null
      },
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [ 15.6588988, 50.68574    ],
          [ 15.6590092, 50.6856876  ],
          [ 15.6589865, 50.685603   ],
          [ 15.658614,  50.6854409  ],
          [ 15.6582412, 50.6853081  ],
          "... (40 points total)"
        ]
      }
    },
    {
      "type": "Feature",
      "properties": {
        "highway": "secondary",
        "surface": "asphalt",
        "tracktype": null,
        "bicycle": null,
        "stav_sil": "dobrý"
      },
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [ 15.7913826, 50.2319462 ],
          [ 15.7914439, 50.2318299 ],
          [ 15.7914613, 50.2317844 ],
          [ 15.791468,  50.2317261 ],
          [ 15.7914516, 50.2316641 ],
          [ 15.7913863, 50.2315047 ],
          [ 15.7913366, 50.2313537 ]
        ]
      }
    },
    {
      "type": "Feature",
      "properties": {
        "highway": "secondary",
        "surface": null,
        "tracktype": null,
        "bicycle": null,
        "stav_sil": null
      },
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [ 15.7753917, 50.2016477 ],
          [ 15.7755762, 50.201626  ],
          [ 15.7758307, 50.2016059 ],
          [ 15.7759706, 50.2015996 ],
          [ 15.776114,  50.2015991 ],
          [ 15.7762856, 50.2016055 ]
        ]
      }
    },
    {
      "type": "Feature",
      "properties": {
        "highway": "primary",
        "surface": "asphalt",
        "tracktype": null,
        "bicycle": null,
        "stav_sil": null
      },
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [ 15.8475487, 50.2113177 ],
          [ 15.8475199, 50.2113646 ]
        ]
      }
    }
  ]
}
```
