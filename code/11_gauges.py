import io

import geopandas as gpd
import numpy as np
import pandas as pd
import requests
import xarray as xr

import climate_tools as ct

ghcn_url = 'https://www.ncei.noaa.gov/pub/data/ghcn/daily'
station_url = 'https://noaa-ghcn-pds.s3.amazonaws.com/csv/by_station/{id}.csv'
max_distance_km = 3
min_record_years = 10
min_days_per_water_year = 335
min_water_years = 5
mountain_stations = {'USC00042327': 'JOTR', 'USC00048317': 'JOTR',
                     'USC00044211': 'JOTR'}
observations = ['prism_4km', 'era5', 'era5_land', 'pierce']
model_datasets = ['caladapt_loca2', 'cmip6', 'isimip3b']
raw_dir = ct.repo / 'data' / 'raw' / 'gauges'
out_dir = ct.processed_dir / 'gauges'


def read_fixed_width(name, colspecs, names):
    text = requests.get(f'{ghcn_url}/{name}', timeout=300).text
    return pd.read_fwf(io.StringIO(text), colspecs=colspecs, names=names)


def precipitation_stations():
    stations = read_fixed_width(
        'ghcnd-stations.txt', [(0, 11), (12, 20), (21, 30), (31, 37), (41, 71)],
        ['id', 'lat', 'lon', 'elevation_m', 'name'])
    inventory = read_fixed_width(
        'ghcnd-inventory.txt', [(0, 11), (31, 35), (36, 40), (41, 45)],
        ['id', 'element', 'first_year', 'last_year'])
    inventory = inventory[inventory.element == 'PRCP'].drop(columns='element')
    stations = stations.merge(inventory, on='id')
    return gpd.GeoDataFrame(
        stations, geometry=gpd.points_from_xy(stations.lon, stations.lat),
        crs='EPSG:4326').to_crs(ct.equal_area_crs)


def distance_to_park_km(stations, park):
    return (stations.distance(park.geometry) / 1000).round(1)


def stations_near_park(stations, park):
    distance_km = distance_to_park_km(stations, park)
    near = stations[distance_km <= max_distance_km]
    record_years = near.last_year - near.first_year + 1
    return near[record_years >= min_record_years].assign(
        park=park.unit, distance_km=distance_km,
        selection=f'in park or within {max_distance_km} km')


def mountain_reference_stations(stations, parks):
    selected = []
    for station_id, park_code in mountain_stations.items():
        park = parks[parks.unit == park_code].iloc[0]
        station = stations[stations.id == station_id]
        selected.append(station.assign(
            park=park_code, distance_km=distance_to_park_km(station, park),
            selection='mountain station used by PRISM'))
    return pd.concat(selected)


def select_stations():
    parks = ct.load_units().query(
        "level == 'park' and not california_only").to_crs(ct.equal_area_crs)
    stations = precipitation_stations()
    near_parks = pd.concat([stations_near_park(stations, park)
                            for park in parks.itertuples()])
    selected = pd.concat([near_parks,
                          mountain_reference_stations(stations, parks)])
    return selected.to_crs('EPSG:4326')


def daily_precipitation(station_id):
    path = raw_dir / f'{station_id}.csv'
    if not path.exists():
        daily = pd.read_csv(station_url.format(id=station_id), dtype=str)
        daily[daily.ELEMENT == 'PRCP'].to_csv(path, index=False)
    daily = pd.read_csv(path, dtype={'Q_FLAG': str})
    daily = daily[daily.Q_FLAG.isna()]
    return pd.DataFrame({
        'date': pd.to_datetime(daily.DATE.astype(str)),
        'pr_mm': daily.DATA_VALUE / 10})


def gauge_water_years(station_id):
    daily = daily_precipitation(station_id)
    october_to_december = daily.date.dt.month >= 10
    daily['water_year'] = np.where(october_to_december,
                                   daily.date.dt.year + 1, daily.date.dt.year)
    totals = (daily.groupby('water_year')
              .agg(pr_mm=('pr_mm', 'sum'), days_reported=('pr_mm', 'size'))
              .reset_index())
    return totals.assign(
        id=station_id, source='gauge',
        complete=totals.days_reported >= min_days_per_water_year)


def keep_stations_with_enough_years(stations, gauges):
    complete_years = gauges[gauges.complete].groupby('id').water_year.count()
    enough = complete_years.index[complete_years >= min_water_years]
    return stations[stations.id.isin(enough)], gauges[gauges.id.isin(enough)]


def dataset_at_gauges(stations, dataset, path=None):
    path = path or ct.processed_dir / dataset / f'{dataset}_water_year_pr.nc'
    water_year_pr = xr.open_dataarray(path)
    values = water_year_pr.sel(
        lat=xr.DataArray(stations.lat.values, dims='id'),
        lon=xr.DataArray(stations.lon.values, dims='id'), method='nearest')
    return (values.assign_coords(id=stations.id.values)
            .rename('pr_mm').to_dataframe().reset_index()
            [['id', 'water_year', 'pr_mm']].assign(source=dataset))


def model_runs_at_gauges(stations, dataset):
    paths = sorted((ct.processed_dir / dataset).glob('*_water_year_pr.nc'))
    return pd.concat([
        dataset_at_gauges(stations, dataset, path).assign(
            model=xr.open_dataarray(path).attrs['model'])
        for path in paths])


def model_means(model_runs):
    return (model_runs.groupby(['source', 'id', 'water_year'])
            .agg(pr_mm=('pr_mm', 'mean'), n_models=('pr_mm', 'size'))
            .reset_index().assign(source=lambda d: d.source + '_mean'))


raw_dir.mkdir(parents=True, exist_ok=True)
out_dir.mkdir(parents=True, exist_ok=True)

stations = select_stations()
gauges = pd.concat([gauge_water_years(station_id)
                    for station_id in stations.id.unique()])
stations, gauges = keep_stations_with_enough_years(stations, gauges)
unique_stations = stations.drop_duplicates('id')
observed = pd.concat([dataset_at_gauges(unique_stations, dataset)
                      for dataset in observations])
model_runs = pd.concat([model_runs_at_gauges(unique_stations, dataset)
                        for dataset in model_datasets])

stations.drop(columns='geometry').to_csv(out_dir / 'gauge_stations.csv',
                                         index=False)
pd.concat([gauges, observed]).to_csv(out_dir / 'gauges_water_year_pr.csv',
                                     index=False)
model_runs.to_csv(out_dir / 'gauges_model_runs_water_year_pr.csv', index=False)
model_means(model_runs).to_csv(
    out_dir / 'gauges_model_means_water_year_pr.csv', index=False)
print(stations[['park', 'id', 'name', 'distance_km', 'selection']]
      .to_string(index=False))
