import sys
import time

import fsspec
import xarray as xr

import climate_tools as ct

base_url = ('https://cirrus.ucsd.edu/~pierce/nonsplit_precip/precip/'
            'livneh_unsplit_precip.2021-05-02.{year}.nc')
years = range(1950, 2019)
yearly_dir = ct.repo / 'data' / 'interim' / 'pierce'
yearly_dir.mkdir(parents=True, exist_ok=True)


def read_year(year):
    with fsspec.open(base_url.format(year=year), block_size=2**18) as remote:
        daily_mm = xr.open_dataset(remote, engine='h5netcdf')['PRCP']
        daily_mm = ct.crop_to_mojave(ct.standardise_coordinates(
            daily_mm.rename(Time='time'))).load()
    return daily_mm.resample(time='MS').sum(min_count=1)


def monthly_file(year, attempts=5):
    path = yearly_dir / f'pierce_monthly_{year}.nc'
    if path.exists():
        return path
    for attempt in range(attempts):
        try:
            partial_path = path.with_suffix('.partial')
            read_year(year).to_netcdf(partial_path)
            partial_path.rename(path)
            print(f'read {year}', flush=True)
            return path
        except Exception as error:
            print(f'retrying {year} after {type(error).__name__}', flush=True)
            time.sleep(60)
    raise RuntimeError(f'could not read {year}')


if len(sys.argv) == 3:
    for year in range(int(sys.argv[1]), int(sys.argv[2]) + 1):
        monthly_file(year)
else:
    files = [monthly_file(year) for year in years]
    monthly_mm = xr.open_mfdataset(files)['PRCP'].load()
    ct.save_water_year_map(ct.water_year_totals(monthly_mm), 'pierce')
