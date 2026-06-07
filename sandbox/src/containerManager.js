 
const Docker = require('dockerode');
const docker = new Docker();

async function spawnContestantContainer(imageTag, submissionId) {
  const container = await docker.createContainer({
    Image: imageTag,
    name: `contestant-${submissionId}`,
    HostConfig: {
      Memory: 512 * 1024 * 1024,        
      CpuPeriod: 100000,
      CpuQuota: 200000,                  
      NetworkMode: 'contestant-net',     
      ReadonlyRootfs: true,              
      CapDrop: ['ALL'],                  
      SecurityOpt: ['no-new-privileges'],
    },
    ExposedPorts: { '8080/tcp': {} },
    PortBindings: { '8080/tcp': [{ HostPort: '0' }] },  
  });

  await container.start();
  const data = await container.inspect();
  const port = data.NetworkSettings.Ports['8080/tcp'][0].HostPort;
  return { containerId: container.id, port };
}

module.exports = { spawnContestantContainer };