// Edit these two values once before publishing.
const REPO_URL = "https://github.com/YOUR-USERNAME/8byte-devops-assignment";
const LINKEDIN_URL = "https://www.linkedin.com/";

const repoLinks = document.querySelectorAll('[data-repo]');
repoLinks.forEach(a => a.href = REPO_URL);
document.querySelectorAll('[data-repo-path]').forEach(a => a.href = `${REPO_URL}/tree/main/${a.dataset.repoPath}`);
document.querySelectorAll('[data-repo-file]').forEach(a => a.href = `${REPO_URL}/blob/main/${a.dataset.repoFile}`);
document.querySelectorAll('[data-repo-file]').forEach(a => a.target = '_blank');

document.querySelectorAll('footer a[href*="linkedin.com"]').forEach(a => a.href = LINKEDIN_URL);

const progress = document.getElementById('scrollProgress');
window.addEventListener('scroll', () => {
  const max = document.documentElement.scrollHeight - innerHeight;
  progress.style.width = `${max > 0 ? scrollY / max * 100 : 0}%`;
}, {passive:true});

const menuToggle = document.getElementById('menuToggle');
const navMenu = document.getElementById('navMenu');
menuToggle?.addEventListener('click', () => {
  const open = navMenu.classList.toggle('open');
  menuToggle.setAttribute('aria-expanded', open);
});
navMenu?.querySelectorAll('a').forEach(a => a.addEventListener('click', () => navMenu.classList.remove('open')));

const panels = {
  infra: {
    title:'Infrastructure as Code',
    text:'Terraform defines the network, security groups, IAM, EC2, RDS, ALB, ECR, Secrets Manager and alerting resources so the environment can be recreated consistently.',
    list:['VPC with 2 public + 2 private subnets across 2 AZs','Private EC2 and RDS; ALB is the public ingress','S3 remote state with encryption and versioning','SSM Session Manager instead of SSH']
  },
  delivery: {
    title:'Automated application delivery',
    text:'The FastAPI service is containerized, stored in ECR and moved through staging automatically after merges. Production requires explicit confirmation and approval.',
    list:['Docker image tagged with the Git SHA','ECR repository with lifecycle policy','SSM SendCommand deploys to private EC2','ALB health check validates the deployed service']
  },
  observe: {
    title:'Observability & alerting',
    text:'EC2 infrastructure metrics are scraped by Prometheus and visualized in Grafana. RDS metrics come from CloudWatch, while SNS delivers alert notifications.',
    list:['Node Exporter metrics scraped every 15 seconds','Grafana dashboards for EC2 and RDS','7 CloudWatch alarms across EC2 + RDS','SNS email notifications for threshold breaches']
  },
  secure: {
    title:'Security by design',
    text:'Security controls were built into the network, identity, secret, host and container layers. The production pipeline intentionally blocks vulnerable releases.',
    list:['No public IPs on EC2 or RDS','Secrets Manager for DB and Grafana credentials','SSM replaces SSH and port 22','CRITICAL Trivy findings block production']
  }
};
const reqCards = document.querySelectorAll('.req-card');
const panelTitle = document.getElementById('panelTitle');
const panelText = document.getElementById('panelText');
const panelList = document.getElementById('panelList');
reqCards.forEach(card => card.addEventListener('click', () => {
  reqCards.forEach(c => c.classList.remove('active'));
  card.classList.add('active');
  const p = panels[card.dataset.panel];
  panelTitle.textContent = p.title;
  panelText.textContent = p.text;
  panelList.innerHTML = p.list.map(x => `<li>${x}</li>`).join('');
}));

const lightbox = document.getElementById('lightbox');
const lightboxImg = document.getElementById('lightboxImg');
const closeLightbox = () => { lightbox.classList.remove('open'); lightbox.setAttribute('aria-hidden','true'); };
document.querySelectorAll('.screenshot-grid img, .evidence-split img').forEach(img => img.addEventListener('click', () => {
  lightboxImg.src = img.src;
  lightboxImg.alt = img.alt;
  lightbox.classList.add('open');
  lightbox.setAttribute('aria-hidden','false');
}));
document.getElementById('lightboxClose').addEventListener('click', closeLightbox);
lightbox.addEventListener('click', e => { if(e.target === lightbox) closeLightbox(); });
document.addEventListener('keydown', e => { if(e.key === 'Escape') closeLightbox(); });
