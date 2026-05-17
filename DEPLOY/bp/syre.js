// Initialize Swiper Carousel
        var swiper = new Swiper('.swiper', {
            pagination: {
                el: '.swiper-pagination',
                clickable: true,
            },
            autoplay: {
                delay: 2500,
                disableOnInteraction: false,
            },
            loop: true
        });
        // ECharts Color Palette
        const syreColors = {
            primary: '#8a2be2',    // Purple
            secondary: '#ff007f',  // Pink
            accent: '#00c9ff',     // Cyan
            dark: '#333333',
            light: '#f0f0f0',
            success: '#4A7C59',
            warning: '#D97706'
        };
        // EChart 1: Donation Funnel (50% Commercial / 50% Social)
        const donationFunnelChart = echarts.init(document.getElementById('donationFunnelChart'), null, {renderer: 'svg'});
        donationFunnelChart.setOption({
            title: {
                text: 'SYRE™ Donasjonstrakt: 50/50 Kommersielt/Sosialt Modell',
                left: 'center',
                textStyle: { fontSize: 18, fontWeight: 'bold' }
            },
            tooltip: {
                trigger: 'item',
                formatter: '{b}: {c} par sko<br/>({d}%)'
            },
            series: [{
                type: 'funnel',
                left: '10%',
                top: '60',
                width: '80%',
                minSize: '30%',
                maxSize: '100%',
                sort: 'descending',
                gap: 2,
                label: {
                    show: true,
                    position: 'inside',
                    formatter: '{b}
{c} par',

                    fontSize: 14
                },
                labelLine: {
                    length: 10,
                    lineStyle: { width: 1 }
                },
                itemStyle: {
                    borderColor: '#fff',
                    borderWidth: 2
                },
                emphasis: {
                    label: { fontSize: 16, fontWeight: 'bold' }
                },
                data: [
                    { value: 25000, name: 'Produksjon Total (År 3)', itemStyle: { color: syreColors.primary } },
                    { value: 12500, name: 'Kommersielt Salg (50%)', itemStyle: { color: syreColors.accent } },
                    { value: 12500, name: 'Gratis Donasjoner (50%)', itemStyle: { color: syreColors.secondary } },
                    { value: 6250, name: 'Kirkens Bymisjon', itemStyle: { color: '#e89b7e' } },
                    { value: 3750, name: 'Blå Kors', itemStyle: { color: '#c15f3c' } },
                    { value: 2500, name: 'Frelsesarmeen & Røde Kors', itemStyle: { color: '#da7756' } }
                ]
            }]
        });
        // EChart 2: Market Penetration Curve (12% Year 3 Target)
        const marketPenetrationChart = echarts.init(document.getElementById('marketPenetrationChart'), null, {renderer: 'svg'});
        marketPenetrationChart.setOption({
            title: {
                text: 'Markedspenetrasjonsanalyse: SYRE™ vs. Norge Premium Fottøy',
                left: 'center',
                textStyle: { fontSize: 18, fontWeight: 'bold' }
            },
            tooltip: {
                trigger: 'axis',
                axisPointer: { type: 'cross' }
            },
            legend: {
                data: ['SYRE™ Markedsandel (%)', 'Kumulativ Omsetning (MNOK)', 'Kunde-base (antall)'],
                top: 40
            },
            grid: {
                left: '3%',
                right: '4%',
                bottom: '10%',
                containLabel: true
            },
            xAxis: {
                type: 'category',
                boundaryGap: false,
                data: ['Lansering', 'Q2 År 1', 'Q4 År 1', 'Q2 År 2', 'Q4 År 2', 'Q2 År 3', 'Q4 År 3 (12%)']
            },
            yAxis: [
                {
                    type: 'value',
                    name: 'Markedsandel (%)',
                    position: 'left',
                    axisLabel: { formatter: '{value} %' },
                    max: 15
                },
                {
                    type: 'value',
                    name: 'Omsetning (MNOK)',
                    position: 'right',
                    axisLabel: { formatter: '{value} M' }
                }
            ],
            series: [
                {
                    name: 'SYRE™ Markedsandel (%)',
                    type: 'line',
                    smooth: true,
                    data: [0, 1.5, 3.2, 5.8, 7.5, 10.2, 12.0],
                    itemStyle: { color: syreColors.primary },
                    areaStyle: { opacity: 0.3 },
                    markPoint: {
                        data: [
                            { type: 'max', name: 'Mål År 3: 12%' }
                        ]
                    },
                    markLine: {
                        data: [
                            { type: 'average', name: 'Gjennomsnitt' }
                        ]
                    }
                },
                {
                    name: 'Kumulativ Omsetning (MNOK)',
                    type: 'line',
                    yAxisIndex: 1,
                    smooth: true,
                    data: [0, 2, 5, 10, 17, 30, 42],
                    itemStyle: { color: syreColors.secondary }
                },
                {
                    name: 'Kunde-base (antall)',
                    type: 'bar',
                    yAxisIndex: 1,
                    data: [0, 0.8, 2.1, 4.2, 7, 12.5, 17.5],
                    itemStyle: { color: syreColors.accent, opacity: 0.5 }
                }
            ]
        });
        // EChart 3: Financial Waterfall (NOK 2M Innovasjon Norge Funding Flow)
        const financialWaterfallChart = echarts.init(document.getElementById('financialWaterfallChart'), null, {renderer: 'svg'});
        financialWaterfallChart.setOption({
            title: {
                text: 'Finansiell Waterfall: NOK 2M Innovasjon Norge Kapitalflyt',
                subtext: 'Hvordan offentlig støtte flyter gjennom verdikjeden',
                left: 'center',
                textStyle: { fontSize: 18, fontWeight: 'bold' }
            },
            tooltip: {
                trigger: 'axis',
                axisPointer: { type: 'shadow' },
                formatter: function(params) {
                    let tar = params[1];
                    return tar.name + '<br/>' + tar.seriesName + ': ' + tar.value + ' NOK';
                }
            },
            grid: {
                left: '3%',
                right: '4%',
                bottom: '3%',
                containLabel: true
            },
            xAxis: {
                type: 'category',
                splitLine: { show: false },
                data: ['Startkapital
(Total)', 'Innovasjon

Norge', 'Private

Investors', 'SPEIS

Samfinansiering', 'SkatteFUNN', 'FoU

(35%)', 'Produksjon

(30%)', 'Marketing

(20%)', 'Social Impact

(10%)', 'Drift

(5%)', 'Restkapital'],

                axisLabel: {
                    interval: 0,
                    rotate: 0,
                    fontSize: 11
                }
            },
            yAxis: {
                type: 'value',
                name: 'NOK (tusener)',
                axisLabel: {
                    formatter: function(value) {
                        return (value / 1000).toFixed(1) + 'M';
                    }
                }
            },
            series: [
                {
                    name: 'Placeholder',
                    type: 'bar',
                    stack: 'Total',
                    itemStyle: {
                        borderColor: 'transparent',
                        color: 'transparent'
                    },
                    emphasis: {
                        itemStyle: {
                            borderColor: 'transparent',
                            color: 'transparent'
                        }
                    },
                    data: [0, 0, 0, 2500, 5000, 0, 2100, 3900, 5100, 5700, 0]
                },
                {
                    name: 'Kapital',
                    type: 'bar',
                    stack: 'Total',
                    label: {
                        show: true,
                        position: 'top',
                        formatter: function(params) {
                            let val = params.value / 1000;
                            return val > 0 ? val.toFixed(1) + 'M' : '';
                        }
                    },
                    data: [
                        6000,  // Total start
                        2000,  // Innovasjon Norge (green)
                        2500,  // Private (green)
                        1000,  // SPEIS (green)
                        500,   // SkatteFUNN (green)
                        -2100, // FoU cost (red)
                        -1800, // Production cost (red)
                        -1200, // Marketing cost (red)
                        -600,  // Social Impact cost (red)
                        -300,  // Drift cost (red)
                        0      // Rest (gray, calculated)
                    ],
                    itemStyle: {
                        color: function(params) {
                            if (params.dataIndex === 0 || params.dataIndex === 10) return '#808080'; // Gray for total
                            if (params.value > 0) return '#4A7C59'; // Green for income
                            return '#DC2626'; // Red for costs
                        }
                    }
                }
            ]
        });
        // Keep existing Chart.js chart for Financial Projections (compatibility)
        const financeCtx = document.getElementById('financeChart').getContext('2d');
        // Note: Chart.js is still needed for this one legacy chart, but we're transitioning to ECharts
        // For full ECharts migration, this would be replaced too, but keeping minimal change approach

// Financial Projections Chart (Chart.js - keeping for backward compatibility)
        const financeChart = new Chart(financeCtx, {
            type: 'bar',
            data: {
                labels: ['År 1', 'År 2', 'År 3'],
                datasets: [
                    {
                        label: 'Omsetning (MNOK)',
                        data: [5, 12, 25],
                        backgroundColor: '#8a2be2',
                    },
                    {
                        label: 'Netto Resultat (MNOK)',
                        data: [-1, 2, 6],
                        backgroundColor: '#333333',
                    },
                    {
                        label: 'Donerte sko (antall)',
                        data: [2500, 6000, 12500],
                        backgroundColor: '#ff007f',
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                scales: {
                    y: { beginAtZero: true },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        grid: { drawOnChartArea: false }
                    }
                },
                plugins: {
                    title: { display: true, text: 'Økonomiske Prognoser og Samfunnsimpakt' },
                    legend: { position: 'bottom' }
                }
            }
        });
        // Growth Trends Line Chart (Chart.js)
        const growthCtx = document.getElementById('growthChart').getContext('2d');
        const growthChart = new Chart(growthCtx, {
            type: 'line',
            data: {
                labels: ['2022', '2023', '2024', '2025'],
                datasets: [{
                    label: 'Årlig Vekst (%)',
                    data: [5, 8, 10, 12],
                    backgroundColor: 'rgba(138, 43, 226, 0.2)',
                    borderColor: '#8a2be2',
                    fill: true,
                }]
            },
            options: {
                plugins: {
                    title: { display: true, text: 'Forventet Markedsvekst' }
                },
                scales: { y: { beginAtZero: true } }
            }
        });