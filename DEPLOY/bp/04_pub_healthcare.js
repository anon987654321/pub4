// Chart.js visualizations for ECharts-style data presentation

    // 1. Medication Production Timeline (24-hour cycle)
    const timelineCtx = document.getElementById('timelineChart');
    if (timelineCtx) {

      new Chart(timelineCtx, {

        type: 'bar',
        data: {

          labels: ['Prescription

Received', 'AI Recipe

Optimization', 'Synthesis

Execution', 'Quality

Control', 'Packaging

& Dispensing'],

          datasets: [{

            label: 'Hours',

            data: [0.5, 2, 18, 2.5, 1],

            backgroundColor: '#DA7756',

            borderColor: '#C15F3C',

            borderWidth: 1

          }]

        },

        options: {

          responsive: true,

          plugins: {

            legend: { display: false },

            title: {

              display: true,

              text: 'From Prescription to Production: 24 Hours',

              font: { size: 16, family: 'Source Serif 4' }

            }

          },

          scales: {

            y: {

              beginAtZero: true,

              title: { display: true, text: 'Hours' }

            }

          }

        }

      });

    }

    // 2. Norwegian Hospital Network Deployment

    const deploymentCtx = document.getElementById('deploymentChart');

    if (deploymentCtx) {

      new Chart(deploymentCtx, {

        type: 'line',
        data: {

          labels: ['Q1

Year 1', 'Q2

Year 1', 'Q3

Year 1', 'Q4

Year 1', 'Q1

Year 2', 'Q2

Year 2', 'Q3

Year 2', 'Q4

Year 2', 'Q1

Year 3', 'Q2

Year 3', 'Q3

Year 3', 'Q4

Year 3'],

          datasets: [{

            label: 'Cumulative Installations',

            data: [1, 2, 3, 3, 8, 12, 18, 25, 40, 60, 75, 90],

            backgroundColor: 'rgba(218, 119, 86, 0.2)',

            borderColor: '#DA7756',

            borderWidth: 2,

            fill: true,

            tension: 0.4

          }]

        },

        options: {

          responsive: true,

          plugins: {

            legend: { display: true },

            title: {

              display: true,

              text: '55 Hospital Installations Over 3 Years',

              font: { size: 16, family: 'Source Serif 4' }

            }

          },

          scales: {

            y: {

              beginAtZero: true,

              title: { display: true, text: 'Installations' }

            }

          }

        }

      });

    }

    // 3. Cost Reduction Curve

    const costCtx = document.getElementById('costChart');

    if (costCtx) {

      new Chart(costCtx, {

        type: 'line',
        data: {

          labels: ['Year 1

Pilot', 'Year 2

Scale', 'Year 3

Optimize', 'Year 4

Mature'],

          datasets: [{

            label: 'Cost per Dose (NOK)',

            data: [150, 85, 35, 30],

            backgroundColor: 'rgba(193, 95, 60, 0.2)',

            borderColor: '#C15F3C',

            borderWidth: 2,

            fill: true,

            tension: 0.4

          }]

        },

        options: {

          responsive: true,

          plugins: {

            legend: { display: true },

            title: {

              display: true,

              text: '77% Cost Reduction Through Automation',

              font: { size: 16, family: 'Source Serif 4' }

            }

          },

          scales: {

            y: {

              beginAtZero: true,

              title: { display: true, text: 'NOK per Dose' }

            }

          }

        }

      });

    }

    // 4. Social Impact Dashboard

    const impactCtx = document.getElementById('impactChart');

    if (impactCtx) {

      new Chart(impactCtx, {

        type: 'bar',
        data: {

          labels: ['Nordland', 'Troms', 'Finnmark', 'Møre og

Romsdal', 'Sogn og

Fjordane', 'Oppland', 'Hedmark'],

          datasets: [{

            label: 'Patients Served',

            data: [15000, 12000, 8000, 18000, 14000, 11000, 10000],

            backgroundColor: '#DA7756',

            borderColor: '#C15F3C',

            borderWidth: 1

          }]

        },

        options: {

          responsive: true,

          plugins: {

            legend: { display: true },

            title: {

              display: true,

              text: 'Rural Healthcare Access: 88,000 Patients Year 3',

              font: { size: 16, family: 'Source Serif 4' }

            }

          },

          scales: {

            y: {

              beginAtZero: true,

              title: { display: true, text: 'Patients Served' }

            }

          }

        }

      });

    }
