// Nordic Prosperity Fund Allocation Chart

        const prosperityCtx = document.getElementById('prosperityChart').getContext('2d');

        const prosperityChart = new Chart(prosperityCtx, {
            type: 'doughnut',
            data: {

                labels: ['Nordiske aksjer', 'Internasjonale aksjer', 'Obligasjoner', 'Kryptovalutaer', 'Råvarer'],
                datasets: [{
                    data: [40, 30, 15, 10, 5],
                    backgroundColor: ['#5d93ff', '#ff007f', '#00c9ff', '#ffcc00', '#8a2be2'],
                }]
            },
            options: {
                plugins: {
                    title: { display: true, text: 'Nordic Prosperity Fund - Asset Allokering' },
                    legend: { position: 'bottom' }
                }
            }
        });
        // Ruby Bot Performance Chart
        const botCtx = document.getElementById('botChart').getContext('2d');
        const botChart = new Chart(botCtx, {
            type: 'line',
            data: {
                labels: ['Jan', 'Feb', 'Mar', 'Apr', 'Mai', 'Jun'],

                datasets: [{
                    label: 'Skalperingsroboter (%)',
                    data: [2.5, 3.1, 2.8, 3.5, 4.2, 3.8],
                    borderColor: '#5d93ff',
                    backgroundColor: 'rgba(93, 147, 255, 0.1)',
                    fill: true
                }, {
                    label: 'Arbitrasje-bots (%)',
                    data: [1.8, 2.2, 2.5, 2.1, 2.8, 3.2],
                    borderColor: '#ff007f',
                    backgroundColor: 'rgba(255, 0, 127, 0.1)',
                    fill: true
                }]
            },
            options: {
                plugins: {
                    title: { display: true, text: 'Ruby Bot Swarm - Månedlig Avkastning' }
                },
                scales: { y: { beginAtZero: true } }
            }
        });
        // AI³ Performance Metrics
        const ai3Ctx = document.getElementById('ai3Chart').getContext('2d');
        const ai3Chart = new Chart(ai3Ctx, {
            type: 'radar',
            data: {
                labels: ['Risikoanalyse', 'Porteføljeoptimalisering', 'Markedsforutsigelse', 'Handelsautomatisering', 'Rapportering'],

                datasets: [{
                    label: 'AI³ Ytelse',
                    data: [92, 88, 85, 95, 90],
                    backgroundColor: 'rgba(93, 147, 255, 0.2)',
                    borderColor: '#5d93ff',
                    borderWidth: 2
                }]
            },
            options: {
                plugins: {
                    title: { display: true, text: 'AI³ System Kapabiliteter (%)' }
                },
                scales: {
                    r: { beginAtZero: true, max: 100 }
                }
            }
        });
        // Historical Performance Chart
        const performanceCtx = document.getElementById('performanceChart').getContext('2d');
        const performanceChart = new Chart(performanceCtx, {
            type: 'line',
            data: {
                labels: ['2020', '2021', '2022', '2023', '2024', '2025E'],

                datasets: [{
                    label: 'Norwegian Hedge (%)',
                    data: [15.5, 18.2, 12.8, 16.9, 19.5, 17.0],
                    borderColor: '#5d93ff',
                    backgroundColor: 'rgba(93, 147, 255, 0.1)',
                    fill: true
                }, {
                    label: 'OSEBX (%)',
                    data: [8.2, 12.5, -2.1, 10.3, 8.9, 7.5],
                    borderColor: '#cccccc',
                    backgroundColor: 'rgba(200, 200, 200, 0.1)',
                    fill: true
                }]
            },
            options: {
                plugins: {
                    title: { display: true, text: 'Historisk Avkastning vs Benchmark' }
                },
                scales: { y: { beginAtZero: false } }
            }
        });