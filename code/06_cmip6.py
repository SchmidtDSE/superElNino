import re

import intake
import xarray as xr

import climate_tools as ct

catalog_url = 'https://storage.googleapis.com/cmip6/pangeo-cmip6.json'
models = ['ACCESS-CM2', 'CESM2', 'CNRM-ESM2-1', 'EC-Earth3', 'EC-Earth3-Veg',
          'FGOALS-g3', 'GFDL-ESM4', 'HadGEM3-GC31-LL', 'INM-CM5-0',
          'IPSL-CM6A-LR', 'KACE-1-0-G', 'MIROC6', 'MPI-ESM1-2-HR',
          'MRI-ESM2-0', 'TaiESM1', 'UKESM1-0-LL']
catalog = intake.open_esm_datastore(catalog_url).df
runs = catalog[(catalog.table_id == 'Amon') & (catalog.variable_id == 'pr') &
               (catalog.experiment_id == 'historical') &
               catalog.source_id.isin(models)]


def realisation(member_id):
    return int(re.match(r'r(\d+)', member_id).group(1))


first_runs = (runs.assign(r=runs.member_id.map(realisation))
              .sort_values(['source_id', 'r', 'member_id', 'version'],
                           ascending=[True, True, True, False])
              .groupby('source_id').head(1))

for run in first_runs.itertuples():
    rate = xr.open_zarr(run.zstore, storage_options={'token': 'anon'},
                        consolidated=True)['pr']
    rate = ct.crop_to_mojave(ct.standardise_coordinates(
        rate.sel(time=slice('1950-01', '2014-12'))))
    monthly_mm = ct.monthly_total_mm(rate.load())
    model = f'{run.source_id}_{run.member_id}'
    ct.save_water_year_map(ct.water_year_totals(monthly_mm), 'cmip6', model)
