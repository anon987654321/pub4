// Color palette from master.json design_system
    const colors = {
      primary: ['#DA7756', '#C15F3C', '#E89B7E', '#4A7C59', '#D97706'],
      neutral: { bg: '#FFFCF7', surface: '#F5F2ED', text: '#3D3929' }
    };

    // 1. Market Size Funnel Chart
    (function(){
      const el = document.getElementById('marketSizeChart');
      if (!el) return;
      const chart = echarts.init(el, null, {renderer: 'svg'});
      chart.setOption({

        title: { text: 'Markedsstørrelse (Norge Begravelsesbransjen)', left: 'center' },
        tooltip: { trigger: 'item', formatter: '{b}: {c} MNOK' },
        series: [{
          type: 'funnel',
          left: '10%',

          width: '80%',
          label: { formatter: '{b}
{c} MNOK' },

          labelLine: { show: false },
          itemStyle: { borderColor: '#fff', borderWidth: 2 },
          data: [
            { value: 2600, name: 'TAM - Norge totalt', itemStyle: { color: colors.primary[0] } },
            { value: 520, name: 'SAM - Oslo-regionen', itemStyle: { color: colors.primary[1] } },
            { value: 18, name: 'SOM - Målbar andel år 3', itemStyle: { color: colors.primary[2] } }
          ]
        }]
      });
      window.addEventListener('resize', () => chart.resize());
    })();
    // 2. Revenue Projection Chart (3 scenarios)
    (function(){
      const el = document.getElementById('revenueChart');
      if (!el) return;

      const chart = echarts.init(el, null, {renderer: 'svg'});
      const years = ['År 1', 'År 2', 'År 3'];

      const conservative = [5.8, 10.2, 13.5];
      const realistic = [8.6, 13.8, 16.8];
      const optimistic = [11.5, 17.2, 20.4];
      chart.setOption({
        title: { text: 'Omsetningsprognoser (MNOK)', left: 'center' },

        tooltip: { trigger: 'axis' },
        legend: { top: 30, data: ['Konservativ', 'Realistisk', 'Optimistisk'] },
        grid: { left: 60, right: 60, bottom: 40, top: 80 },
        xAxis: { type: 'category', data: years },

        yAxis: { type: 'value', name: 'MNOK' },
        series: [
          {
            name: 'Konservativ',
            type: 'line',
            data: conservative,
            smooth: true,
            lineStyle: { color: colors.primary[3], type: 'dashed' },
            itemStyle: { color: colors.primary[3] }
          },
          {
            name: 'Realistisk',
            type: 'line',
            data: realistic,
            smooth: true,
            lineStyle: { color: colors.primary[0], width: 3 },
            itemStyle: { color: colors.primary[0] },
            areaStyle: { color: colors.primary[0], opacity: 0.1 }
          },
          {
            name: 'Optimistisk',
            type: 'line',
            data: optimistic,
            smooth: true,
            lineStyle: { color: colors.primary[4], type: 'dashed' },
            itemStyle: { color: colors.primary[4] }
          }
        ]
      });
      window.addEventListener('resize', () => chart.resize());
    })();
    // 3. Cost Structure Stacked Bar Chart
    (function(){
      const el = document.getElementById('costChart');
      if (!el) return;

      const chart = echarts.init(el, null, {renderer: 'svg'});
      const years = ['År 1', 'År 2', 'År 3'];

      chart.setOption({
        title: { text: 'Kostnadsstruktur (MNOK)', left: 'center' },
        tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
        legend: { top: 30, data: ['COGS', 'OPEX', 'CAPEX'] },
        grid: { left: 60, right: 60, bottom: 40, top: 80 },

        xAxis: { type: 'category', data: years },

        yAxis: { type: 'value', name: 'MNOK' },
        series: [
          {
            name: 'COGS',
            type: 'bar',
            stack: 'total',
            data: [3.2, 5.4, 7.8],
            itemStyle: { color: colors.primary[0] }
          },
          {
            name: 'OPEX',
            type: 'bar',
            stack: 'total',
            data: [2.8, 3.6, 4.4],
            itemStyle: { color: colors.primary[1] }
          },
          {
            name: 'CAPEX',
            type: 'bar',
            stack: 'total',
            data: [0.6, 0.3, 0.2],
            itemStyle: { color: colors.primary[2] }
          }
        ]
      });
      window.addEventListener('resize', () => chart.resize());
    })();
    // 4. Unit Economics Waterfall Chart
    (function(){
      const el = document.getElementById('unitEconomicsChart');
      if (!el) return;

      const chart = echarts.init(el, null, {renderer: 'svg'});
      chart.setOption({

        title: { text: 'Enhetsekonomi per Seremoni (NOK)', left: 'center' },
        tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
        grid: { left: 80, right: 80, bottom: 40, top: 60 },
        xAxis: {
          type: 'category',

          data: ['Inntekt', 'Variable kost.', 'Dekning', 'Faste kost.', 'Nettoresultat']
        },
        yAxis: { type: 'value', name: 'NOK' },
        series: [{
          type: 'bar',
          data: [
            { value: 72000, itemStyle: { color: colors.primary[3] } },
            { value: -42000, itemStyle: { color: colors.primary[4] } },
            { value: 30000, itemStyle: { color: colors.primary[0] } },
            { value: -18000, itemStyle: { color: colors.primary[4] } },
            { value: 12000, itemStyle: { color: colors.primary[3] } }
          ],
          label: {
            show: true,
            position: 'top',
            formatter: (params) => (params.value >= 0 ? '+' : '') + params.value.toLocaleString()
          }
        }]
      });
      window.addEventListener('resize', () => chart.resize());
    })();
    // 5. Cash Flow Chart
    (function(){
      const el = document.getElementById('cashFlowChart');
      if (!el) return;

      const chart = echarts.init(el, null, {renderer: 'svg'});
      const months = ['M1', 'M3', 'M6', 'M9', 'M12', 'M15', 'M18', 'M21', 'M24', 'M27', 'M30', 'M33', 'M36'];

      const cumulative = [-2.5, -2.8, -3.2, -3.4, -3.2, -2.9, -2.4, -1.7, -0.8, 0.2, 1.4, 2.8, 4.5];
      chart.setOption({
        title: { text: 'Kumulativ Kontantstrøm (MNOK)', left: 'center' },
        tooltip: { trigger: 'axis' },
        grid: { left: 60, right: 60, bottom: 40, top: 60 },

        xAxis: { type: 'category', data: months },
        yAxis: { type: 'value', name: 'MNOK' },

        series: [{
          name: 'Kumulativ CF',
          type: 'line',
          data: cumulative,
          smooth: true,
          lineStyle: { color: colors.primary[0], width: 2 },
          itemStyle: { color: colors.primary[0] },
          areaStyle: {
            color: {
              type: 'linear',
              x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: 'rgba(218, 119, 86, 0.3)' },
                { offset: 1, color: 'rgba(218, 119, 86, 0.05)' }
              ]
            }
          },
          markLine: {
            silent: true,
            lineStyle: { color: '#333', type: 'dashed' },
            data: [{ yAxis: 0, label: { formatter: 'Break-even' } }]
          }
        }]
      });
      window.addEventListener('resize', () => chart.resize());
    })();
