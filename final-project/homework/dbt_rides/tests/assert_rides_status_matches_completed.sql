-- status = 'completed' тільки тоді коли є completed_at
-- Перевіряє логіку деривації статусу (completed найвищий пріоритет). Вірно на будь-якому
-- батчі, зокрема коли події приходять не по порядку
select ride_id
from {{ ref('rides') }}
where (status = 'completed') <> (completed_at is not null)
